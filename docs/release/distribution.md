# Distribution

Mactivate uses a zero-cost release path: an ad-hoc-signed disk image on GitHub Releases and a cask in the `HarshitBadam/homebrew-mactivate` tap. The public repository's GitHub-hosted macOS runner builds the Apple Silicon release without paid infrastructure.

## Security boundary

Apple only provides Developer ID signing and notarization through the paid Apple Developer Program. These releases therefore cannot pass Gatekeeper automatically on a new Mac.

Users should try to open Mactivate once, then approve it under **System Settings → Privacy & Security → Open Anyway** if macOS blocks it. They should never disable Gatekeeper.

## Release automation

Conventional commits on `main` maintain a release pull request through Release Please. Merging that pull request creates an immutable version tag and a draft GitHub Release, which triggers a workflow that builds and verifies the disk image, uploads it with its checksum, publishes the GitHub Release, and — once the published artifact is downloaded and re-verified — opens and merges the matching Homebrew tap update. Merging the release pull request is the only manual step in the normal release path.

Published release tags are immutable: a release-tag protection rule and workflow validation keep the tag, the GitHub Release, and the published disk image tied to one fixed commit.

## Install

```bash
brew tap HarshitBadam/mactivate
brew trust --cask HarshitBadam/mactivate/mactivate
brew install --cask mactivate
```

Homebrew requires users to explicitly trust casks from non-official taps. The cask stays outside the official `homebrew/cask` repository because the free build is not notarized.

Alternatively, download the disk image and checksum from the [latest release](https://github.com/HarshitBadam/mactivate/releases/latest).

## Build locally

`version.txt` and the Xcode project's `MARKETING_VERSION` are kept in sync by the release pull request and validated before packaging.

```bash
tools/release/build_dmg.sh <version>
```

The script performs a clean Release build, enforces an arm64 executable, verifies the ad-hoc signature, and creates a drag-to-Applications disk image at:

```text
build/release/dist/Mactivate-<version>.dmg
build/release/dist/Mactivate-<version>.dmg.sha256
```

Maintainer-only release operations (automation credentials, failure recovery, and one-time Homebrew tap setup) live in the [release runbook](runbook.md).
