# AGENTS.md

Instructions for agents working on this repository.

## What this repo is

`illegalstudio/pacman` is an **Arch Linux binary repository served from GitHub
Pages** at <https://illegalstudio.github.io/pacman/>.

It is not a software project: it is an index. It holds the `.pkg.tar.zst` files
of illegalstudio's projects plus the pacman database describing them. Users add
it to `/etc/pacman.conf` and install with `pacman -S`.

Packages are **never added by hand**. Whenever a project publishes a GitHub
Release it notifies this repo; a GitHub Action downloads the package from the
release, updates the database and republishes Pages.

## The full flow

1. A project repo (e.g. `illegalstudio/ggg`) publishes a release.
2. Its workflow calls this repo's reusable workflow
   `.github/workflows/release-package.yml@main`, which builds the `PKGBUILD` in
   an `archlinux:base-devel` container, attaches the `.pkg.tar.zst` to the
   release, and sends a `repository_dispatch` here (`event_type: publish`,
   `client_payload.repo: owner/repo`).
3. `.github/workflows/sync.yml` receives the dispatch and runs
   `scripts/sync.sh`, which downloads the latest release assets, runs
   `repo-add`, deletes previous versions and regenerates `packages.json`.
4. The same workflow commits the result and deploys GitHub Pages.

A nightly cron (`17 4 * * *`) reruns the sync over every source: if a dispatch
is lost, the repo catches up on its own.

## File map

| File | Role |
| --- | --- |
| `scripts/sync.sh` | The actual logic. Download releases → `repo-add` → prune → `packages.json`. |
| `.github/workflows/sync.yml` | Triggers (dispatch / manual / cron), commit, Pages deploy. |
| `.github/workflows/release-package.yml` | Reusable workflow called **by the project repos**. It runs in their context, not here. |
| `.github/workflows/pages.yml` | Pages deploy for hand-made changes (`index.html`, README, …). |
| `sources.json` | List of source repos. Populates itself on first publish. |
| `x86_64/` | Packages and database. **Generated**, see below. |
| `packages.json` | Machine-readable index consumed by `index.html`. **Generated.** |
| `index.html` | Landing page: install instructions plus package list. |
| `docs/example-project*.yml` | Snippets to copy into the project repos. |

## Invariants — do not break these

- **`x86_64/` and `packages.json` are generated.** Do not edit them by hand
  except to remove a package (see README). Changes belong in `sync.sh`.
- **The database is named `illegalstudio`** and must keep matching the section
  name in users' `pacman.conf`. Renaming it breaks every existing install.
- **`illegalstudio.db` and `.files` must be real files, not symlinks.**
  `repo-add` creates symlinks pointing at the `.tar.gz` files; GitHub Pages does
  not follow them. `sync.sh` replaces them with copies — verify if you touch it.
- **`pkgname` is read from the `.PKGINFO` inside the package**, never parsed
  from the file name: names contain dashes and parsing would be ambiguous.
- **Only the latest version of each package is kept**, to stop the git repo from
  growing without bound; older ones remain downloadable from the projects'
  releases.
- **The Pages deploy lives inside `sync.yml`.** Pushes made with `GITHUB_TOKEN`
  do not trigger other workflows, so `sync.yml` cannot delegate to `pages.yml`.
  Do not "simplify" that job away.
- **`actions/checkout` runs inside an `archlinux` container**: the step that
  installs `git` must stay *before* the checkout, otherwise the action falls
  back to downloading a tarball (no `.git`) and the commit fails.
- **`makepkg` refuses to run as root**: in `release-package.yml` the build goes
  through a `builder` user. Do not remove it.
- **No GPG signing**, by choice: users rely on `SigLevel = Optional TrustAll`.
  If signing is ever added, the README must be updated and users have to import
  the key.

## Secrets and permissions

- `PACMAN_DISPATCH_TOKEN` — lives in the **project repos** (ideally as an
  organization secret): a fine-grained PAT with *Contents: read and write*
  scoped to `illegalstudio/pacman`. Used to send the `repository_dispatch`.
- `SOURCES_TOKEN` — optional, **in this repo**. Only needed if some source repo
  is private; otherwise `sync.yml` uses `github.token`.

## Testing changes to sync.sh

`sync.sh` needs `pacman` (`repo-add`), `bsdtar`, `jq` and `gh`. They are all
present on Arch. Any package is enough to exercise the parts that do not hit the
network:

```bash
mkdir -p /tmp/try/x86_64 && cd /tmp/try
echo '{"sources":[]}' > sources.json
cp /var/cache/pacman/pkg/<something>.pkg.tar.zst x86_64/
cp ~/Developer/illegalstudio/pacman/scripts/sync.sh .
repo-add -q -R x86_64/illegalstudio.db.tar.gz x86_64/*.pkg.tar.zst
bash sync.sh && jq . packages.json
```

The full path (release download, dispatch) can only be exercised in CI:
`gh workflow run sync.yml --repo illegalstudio/pacman -f repo=owner/repo`.

## Language

Documentation, comments and commit messages in **English**.
