# illegalstudio · pacman repository

Arch Linux binary repository served from GitHub Pages:
<https://illegalstudio.github.io/pacman/>

Packages are not added by hand: whenever a project publishes a release it
notifies this repository, which downloads the `.pkg.tar.zst` from the release,
updates the pacman database and republishes Pages.

## Using the repository

At the bottom of `/etc/pacman.conf`:

```ini
[illegalstudio]
SigLevel = Optional TrustAll
Server = https://illegalstudio.github.io/pacman/$arch
```

Then:

```bash
sudo pacman -Sy
sudo pacman -S <package>
```

> `SigLevel = Optional TrustAll` because packages are unsigned. Switching to a
> signed repository later does not require changing the URL.

## Adding a project

1. The project needs a `PKGBUILD`.
2. Create a fine-grained PAT with **Contents: read and write** scoped to
   `illegalstudio/pacman` and store it as a `PACMAN_DISPATCH_TOKEN` secret (an
   organization secret is best, so every project inherits it).
3. Copy [`docs/example-project.yml`](docs/example-project.yml) to
   `.github/workflows/pacman.yml` in the project repo.

The package shows up here within a minute of the next release. The source repo
registers itself in `sources.json` on its first publish.

If the project already builds the package itself and attaches it to the release,
use [`docs/example-project-notify-only.yml`](docs/example-project-notify-only.yml)
instead.

## How it works

| Piece | Role |
| --- | --- |
| `.github/workflows/release-package.yml` | Reusable workflow called by the projects: builds the PKGBUILD, attaches the package to the release, sends the `repository_dispatch`. |
| `.github/workflows/sync.yml` | Receives the dispatch, downloads the release assets of the repos in `sources.json`, updates the database, commits and deploys Pages. Also runs nightly as a safety net. |
| `.github/workflows/pages.yml` | Pages deploy for hand-made changes. |
| `scripts/sync.sh` | The actual logic: download, `repo-add`, pruning of old versions, `packages.json` generation. |
| `sources.json` | List of source repos. |
| `x86_64/` | Packages and database served from Pages. |

Only the **latest version** of each package is kept: previous ones are deleted
from this repository (they remain available in the projects' releases).

## Manual operations

```bash
# resync everything (Actions → Sync repository → Run workflow)
gh workflow run sync.yml --repo illegalstudio/pacman

# resync a single project
gh workflow run sync.yml --repo illegalstudio/pacman -f repo=illegalstudio/ggg

# removing a package: drop the repo from sources.json, then
repo-remove x86_64/illegalstudio.db.tar.gz <pkgname>
rm x86_64/<pkgname>-*.pkg.tar.zst
```
