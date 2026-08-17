# Distribution

Mactivate uses a zero-cost release path: an ad-hoc-signed disk image on GitHub Releases and a cask in the `HarshitBadam/homebrew-mactivate` tap. The public repository's GitHub-hosted macOS runner builds the Apple Silicon release without paid infrastructure.

## Security boundary

Apple only provides Developer ID signing and notarization through the paid Apple Developer Program. These releases therefore cannot pass Gatekeeper automatically on a new Mac.

Users should try to open Mactivate once, then approve it under **System Settings → Privacy & Security → Open Anyway** if macOS blocks it. They should never disable Gatekeeper.

## Build locally

`version.txt` and the Xcode project's `MARKETING_VERSION` are kept in sync by the release pull request and validated before packaging.

```bash
tools/release/build_dmg.sh <version>
```

The script creates these ignored artifacts:

```text
build/release/dist/Mactivate-<version>.dmg
build/release/dist/Mactivate-<version>.dmg.sha256
```

It performs a clean Release build, enforces an arm64 executable, verifies the ad-hoc signature, and creates a drag-to-Applications disk image.

## Release automation

Conventional commits on `main` maintain a release pull request through Release Please. The pull request updates `CHANGELOG.md`, `.github/release/release-please-manifest.json`, `version.txt`, and the Xcode `MARKETING_VERSION`. Merge it only after required CI checks pass.

Merging the release pull request creates an immutable version tag and draft GitHub Release. The publication workflow checks out that exact tag, validates its version, builds and verifies the disk image, uploads the disk image, checksum, and generated cask, then publishes the GitHub Release.

After publication, a separate job downloads the public disk image and verifies it against both published SHA-256 values. It also styles, audits, installs, and removes the generated cask. Only after every check passes does the workflow open and squash-merge the Homebrew tap pull request. The release pull request is therefore the only manual approval in the normal release path.

Do not create, move, or delete release tags manually. The release-tag ruleset keeps published source and artifacts tied to one immutable commit.

### Automation credentials

Create a GitHub App installed only on `HarshitBadam/mactivate` and `HarshitBadam/homebrew-mactivate` with these repository permissions:

- Actions: read and write
- Contents: read and write
- Pull requests: read and write

Store its application ID as the `RELEASE_APP_ID` Actions secret and its private key as `RELEASE_APP_PRIVATE_KEY`. The short-lived installation token lets release pull requests trigger CI and lets publication open the cross-repository Homebrew pull request without a personal access token.

Protect `main` with pull requests and require the `Repository policy`, `Swift packages`, and `macOS application` checks. For a solo-maintained repository, required approvals can remain at zero while the checks stay mandatory.

### Recovery

If publication fails while the GitHub Release is still a draft, rerun it from the existing immutable tag:

```bash
gh workflow run release.yml --ref v<version> -f version=<version>
```

If only the Homebrew job fails after publication, rerun the failed job from the original workflow run. This preserves the published assets and repeats only downstream validation and delivery:

```bash
gh run rerun <run-id> --failed
```

## Create the Homebrew tap

The tap is a separate public repository named `HarshitBadam/homebrew-mactivate`. Create it once:

```bash
brew tap-new HarshitBadam/homebrew-mactivate
gh repo create HarshitBadam/homebrew-mactivate \
  --public \
  --source "$(brew --repository HarshitBadam/mactivate)" \
  --remote origin \
  --push
```

Each release automatically opens and merges a versioned pull request in the tap after the public disk image, checksum, cask audit, and installation checks pass.

Users can then install directly:

```bash
brew tap HarshitBadam/mactivate
brew trust --cask HarshitBadam/mactivate/mactivate
brew install --cask mactivate
```

Homebrew requires users to explicitly trust casks from non-official taps. The cask stays outside the official `homebrew/cask` repository because the free build is not notarized.
