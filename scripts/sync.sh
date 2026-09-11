#!/usr/bin/env bash
# Sync the pacman repository with the latest releases of the source repos.
#
#   scripts/sync.sh                  # every repo listed in sources.json
#   scripts/sync.sh owner/repo       # only that repo (registers it if missing)
#
# Requires: pacman (repo-add), bsdtar, jq, gh (with GH_TOKEN exported).

set -euo pipefail

REPO_NAME="${REPO_NAME:-illegalstudio}"
# One directory and one database per architecture. Packages built with
# `arch=(any)` are copied into every one of them.
read -r -a ARCHES <<< "${ARCHES:-x86_64 aarch64}"

only_repo="${1:-}"

# --- auto-register the source repo ------------------------------------------
if [[ -n $only_repo ]]; then
  if ! jq -e --arg r "$only_repo" '.sources | index($r)' sources.json >/dev/null; then
    echo "==> registering new source: $only_repo"
    jq --arg r "$only_repo" '.sources = (.sources + [$r] | unique)' sources.json > sources.json.tmp
    mv sources.json.tmp sources.json
  fi
  sources=("$only_repo")
else
  mapfile -t sources < <(jq -r '.sources[]' sources.json)
fi

for arch in "${ARCHES[@]}"; do mkdir -p "$arch"; done
changed=0

# Read fields from the .PKGINFO inside the package. pkgname in particular must
# never be parsed out of the file name: names contain dashes and parsing them
# would be ambiguous.
pkginfo_field() {
  bsdtar -xOqf "$1" .PKGINFO 2>/dev/null | awk -F ' = ' -v k="$2" '$1==k {print $2; exit}'
}

# Directories a package of the given architecture belongs in.
target_dirs() {
  if [[ $1 == any ]]; then
    printf '%s\n' "${ARCHES[@]}"
  elif [[ " ${ARCHES[*]} " == *" $1 "* ]]; then
    printf '%s\n' "$1"
  fi
}

for src in "${sources[@]:-}"; do
  [[ -n $src ]] || continue
  echo "==> $src"

  if ! tag=$(gh release view --repo "$src" --json tagName -q .tagName 2>/dev/null); then
    echo "    no published release, skipping"
    continue
  fi

  mapfile -t assets < <(
    gh release view "$tag" --repo "$src" --json assets -q '.assets[].name' \
      | grep -E "\.pkg\.tar\.(zst|xz)$" || true
  )

  if [[ ${#assets[@]} -eq 0 ]]; then
    echo "    release $tag has no *.pkg.tar.zst asset, skipping"
    continue
  fi

  for asset in "${assets[@]}"; do
    # The architecture IS unambiguous in the file name (last field before the
    # extension), unlike pkgname. Good enough to skip a download.
    asset_arch="${asset%.pkg.tar.*}"
    asset_arch="${asset_arch##*-}"

    mapfile -t dirs < <(target_dirs "$asset_arch")
    if [[ ${#dirs[@]} -eq 0 ]]; then
      echo "    $asset: architecture $asset_arch not served here, skipping"
      continue
    fi

    missing=0
    for dir in "${dirs[@]}"; do
      [[ -f "$dir/$asset" ]] || missing=1
    done
    if [[ $missing -eq 0 ]]; then
      echo "    $asset already present"
      continue
    fi

    echo "    downloading $asset ($tag)"
    rm -rf tmp && mkdir -p tmp
    gh release download "$tag" --repo "$src" --pattern "$asset" --dir tmp

    pkgname=$(pkginfo_field "tmp/$asset" pkgname)
    if [[ -z $pkgname ]]; then
      echo "    !! $asset is not a valid pacman package, skipping"
      continue
    fi

    # The .PKGINFO is authoritative over the file name
    pkgarch=$(pkginfo_field "tmp/$asset" arch)
    if [[ -n $pkgarch && $pkgarch != "$asset_arch" ]]; then
      mapfile -t dirs < <(target_dirs "$pkgarch")
      if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "    !! $asset declares arch $pkgarch, not served here, skipping"
        continue
      fi
    fi

    for dir in "${dirs[@]}"; do
      # drop previous versions of the same package
      for old in "$dir"/*.pkg.tar.*; do
        [[ -e $old ]] || continue
        [[ $old == *.sig ]] && continue
        if [[ "$(pkginfo_field "$old" pkgname)" == "$pkgname" ]]; then
          echo "    $dir: removing previous version $(basename "$old")"
          rm -f "$old" "$old.sig"
        fi
      done

      cp "tmp/$asset" "$dir/$asset"
      repo-add -q -R "$dir/$REPO_NAME.db.tar.gz" "$dir/$asset"
      echo "    $dir: added $asset"
    done
    changed=1
  done
done

rm -rf tmp

# GitHub Pages does not follow symlinks, and repo-add creates the .db/.files
# entry points as symlinks: replace them with real copies.
for arch in "${ARCHES[@]}"; do
  # repo-add keeps a .old backup of the previous database: not something to
  # commit or to serve
  rm -f "$arch"/*.old
  for ext in db files; do
    target="$arch/$REPO_NAME.$ext.tar.gz"
    [[ -f $target ]] || continue
    rm -f "$arch/$REPO_NAME.$ext"
    cp -f "$target" "$arch/$REPO_NAME.$ext"
  done
done

# --- collect the published packages, once per package -----------------------
# An `any` package lives in every arch directory under the same file name, so
# dedupe on that.
declare -A seen=()
pkg_list=()
for arch in "${ARCHES[@]}"; do
  for pkg in "$arch"/*.pkg.tar.*; do
    [[ -e $pkg ]] || continue
    [[ $pkg == *.sig ]] && continue
    base=$(basename "$pkg")
    [[ -n ${seen[$base]:-} ]] && continue
    seen[$base]=1
    pkg_list+=("$pkg")
  done
done

# --- machine-readable index for the web page --------------------------------
# Regenerated only when something changed, to keep git quiet on no-op runs.
if [[ $changed -eq 1 || ! -f packages.json ]]; then
{
  echo '{'
  echo '  "repo": "'"$REPO_NAME"'",'
  echo '  "updated": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
  echo '  "packages": ['
  first=1
  for pkg in ${pkg_list[@]+"${pkg_list[@]}"}; do
    [[ $first -eq 1 ]] || echo ','
    first=0
    printf '    {"name": %s, "version": %s, "arch": %s, "desc": %s, "url": %s, "file": %s, "size": %s}' \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" pkgname)" '$v')" \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" pkgver)"  '$v')" \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" arch)"    '$v')" \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" pkgdesc)" '$v')" \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" url)"     '$v')" \
      "$(jq -Rn --arg v "$(basename "$pkg")"              '$v')" \
      "$(stat -c%s "$pkg")"
  done
  echo
  echo '  ]'
  echo '}'
} > packages.json
fi

# --- packages table in the README -------------------------------------------
# Deterministic output, so a no-op run leaves git clean.
rows=$(mktemp)
{
  if [[ ${#pkg_list[@]} -eq 0 ]]; then
    echo '_No packages published yet._'
  else
    echo '| Package | Version | Architecture | Description |'
    echo '| --- | --- | --- | --- |'
    for pkg in "${pkg_list[@]}"; do
      name=$(pkginfo_field "$pkg" pkgname)
      ver=$(pkginfo_field "$pkg" pkgver)
      arch=$(pkginfo_field "$pkg" arch)
      desc=$(pkginfo_field "$pkg" pkgdesc | sed 's/|/\\|/g')
      url=$(pkginfo_field "$pkg" url)
      if [[ -n $url ]]; then
        echo "| [\`$name\`]($url) | \`$ver\` | \`$arch\` | $desc |"
      else
        echo "| \`$name\` | \`$ver\` | \`$arch\` | $desc |"
      fi
    done | sort
  fi
} > "$rows"

awk -v f="$rows" '
  index($0, "<!-- packages:start -->") { print; while ((getline l < f) > 0) print l; s = 1; next }
  index($0, "<!-- packages:end -->")   { s = 0 }
  !s { print }
' README.md > README.md.tmp && mv README.md.tmp README.md
rm -f "$rows"

echo "changed=$changed"
[[ -n ${GITHUB_OUTPUT:-} ]] && echo "changed=$changed" >> "$GITHUB_OUTPUT"
exit 0
