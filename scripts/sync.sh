#!/usr/bin/env bash
# Sync the pacman repository with the latest releases of the source repos.
#
#   scripts/sync.sh                  # every repo listed in sources.json
#   scripts/sync.sh owner/repo       # only that repo (registers it if missing)
#
# Requires: pacman (repo-add), bsdtar, jq, gh (with GH_TOKEN exported).

set -euo pipefail

REPO_NAME="${REPO_NAME:-illegalstudio}"
ARCH="${ARCH:-x86_64}"
DB="$ARCH/$REPO_NAME.db.tar.gz"
FILES_DB="$ARCH/$REPO_NAME.files.tar.gz"

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

mkdir -p "$ARCH"
changed=0

# Read pkgname from the .PKGINFO inside the package, never from the file name:
# names contain dashes and parsing them would be ambiguous.
pkginfo_field() {
  bsdtar -xOqf "$1" .PKGINFO 2>/dev/null | awk -F ' = ' -v k="$2" '$1==k {print $2; exit}'
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
    if [[ -f "$ARCH/$asset" ]]; then
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

    # drop previous versions of the same package
    for old in "$ARCH"/*.pkg.tar.*; do
      [[ -e $old ]] || continue
      [[ $old == *.sig ]] && continue
      if [[ "$(pkginfo_field "$old" pkgname)" == "$pkgname" ]]; then
        echo "    removing previous version $(basename "$old")"
        rm -f "$old" "$old.sig"
      fi
    done

    mv "tmp/$asset" "$ARCH/$asset"
    repo-add -q -R "$DB" "$ARCH/$asset"
    changed=1
  done
done

rm -rf tmp

if [[ ! -f $DB ]]; then
  echo "No packages in the repository."
  exit 0
fi

# GitHub Pages does not follow symlinks: these have to be real files
for ext in db files; do
  target="$ARCH/$REPO_NAME.$ext.tar.gz"
  [[ -f $target ]] || continue
  rm -f "$ARCH/$REPO_NAME.$ext"
  cp -f "$target" "$ARCH/$REPO_NAME.$ext"
done

# --- human-readable index for the web page ----------------------------------
# Regenerated only when something changed, to keep git quiet on no-op runs.
if [[ $changed -eq 1 || ! -f packages.json ]]; then
{
  echo '{'
  echo '  "repo": "'"$REPO_NAME"'",'
  echo '  "updated": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
  echo '  "packages": ['
  first=1
  for pkg in "$ARCH"/*.pkg.tar.*; do
    [[ -e $pkg ]] || continue
    [[ $pkg == *.sig ]] && continue
    [[ $first -eq 1 ]] || echo ','
    first=0
    printf '    {"name": %s, "version": %s, "desc": %s, "url": %s, "file": %s, "size": %s}' \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" pkgname)" '$v')" \
      "$(jq -Rn --arg v "$(pkginfo_field "$pkg" pkgver)"  '$v')" \
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

echo "changed=$changed"
[[ -n ${GITHUB_OUTPUT:-} ]] && echo "changed=$changed" >> "$GITHUB_OUTPUT"
exit 0
