<p align="center">
  <img src="assets/logo-mark.svg" alt="illegalstudio pacman repository logo" width="130">
</p>

<h1 align="center">illegalstudio &middot; pacman</h1>

<p align="center">
  <em>An Arch Linux repository that keeps itself up to date.</em>
</p>

<p align="center">
  <a href="https://github.com/illegalstudio/pacman/stargazers"><img src="https://img.shields.io/github/stars/illegalstudio/pacman?style=flat-square&logo=github&logoColor=white&label=stars&color=FFCC00" alt="Stars"></a>
  <a href="https://github.com/illegalstudio/pacman/commits/main"><img src="https://img.shields.io/github/last-commit/illegalstudio/pacman?style=flat-square&logo=github&logoColor=white&label=last%20sync&color=FFCC00" alt="Last sync"></a>
  <a href="https://illegalstudio.github.io/pacman/"><img src="https://img.shields.io/badge/pacman-repository-FFCC00?style=flat-square&logo=archlinux&logoColor=white" alt="Pacman repository"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/illegalstudio/pacman?style=flat-square&color=FFCC00" alt="License: MIT"></a>
  <a href="https://opensource.nahi.me"><img src="https://img.shields.io/badge/open%20source-nahi.me-FFCC00?style=flat-square&logo=firefoxbrowser&logoColor=white" alt="opensource.nahi.me"></a>
</p>

<p align="center">
  <strong>x86_64 &middot; Synced from GitHub Releases &middot; Served from GitHub Pages &middot; Zero maintenance</strong>
</p>

<p align="center">
  A binary Arch Linux repository for illegalstudio's packages, living at
  <a href="https://illegalstudio.github.io/pacman/">illegalstudio.github.io/pacman</a>.
  Nothing is added by hand: when a project publishes a release, this repository
  downloads the <code>.pkg.tar.zst</code>, rebuilds the pacman database and
  republishes Pages on its own.
</p>

<p align="center">
  <a href="https://opensource.nahi.me"><strong>More open source</strong></a>
</p>

---

## Install

Add this at the bottom of `/etc/pacman.conf`:

```ini
[illegalstudio]
SigLevel = Optional TrustAll
Server = https://illegalstudio.github.io/pacman/$arch
```

`$arch` is expanded by pacman: the repository serves **x86_64** and **aarch64**.

Then refresh the package lists and install what you need:

```bash
sudo pacman -Sy
sudo pacman -S <package>
```

Updates arrive like any other package, with `pacman -Syu`.

> Packages are unsigned, hence `SigLevel = Optional TrustAll`. Only the latest
> version of each package is kept here; older ones stay available in each
> project's GitHub releases.

## Packages

<!-- packages:start -->
_No packages published yet._
<!-- packages:end -->
