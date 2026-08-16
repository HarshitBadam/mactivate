# Distribution

Mactivate uses a zero-cost release path: an ad-hoc-signed disk image on GitHub Releases and a cask in the `HarshitBadam/homebrew-mactivate` tap. The public repository's GitHub-hosted macOS runner builds the Apple Silicon release without paid infrastructure.

## Security boundary

Apple only provides Developer ID signing and notarization through the paid Apple Developer Program. These releases therefore cannot pass Gatekeeper automatically on a new Mac.

Users should try to open Mactivate once, then approve it under **System Settings → Privacy & Security → Open Anyway** if macOS blocks it. They should never disable Gatekeeper.

## Build locally

The Xcode project's `MARKETING_VERSION` is the release source of truth.

```bash
tools/release/build_dmg.sh 1.0.1
```

The script creates these ignored artifacts:

```text
build/release/dist/Mactivate-1.0.1.dmg
build/release/dist/Mactivate-1.0.1.dmg.sha256
```

It performs a clean Release build, enforces an arm64 executable, verifies the ad-hoc signature, and creates a drag-to-Applications disk image.

## Publish a GitHub release

After tests pass and the release commit is on `main`, dispatch the release workflow with a new version that matches `MARKETING_VERSION`.

```bash
gh workflow run release.yml --ref main -f version=1.0.1
```

Do not create or move release tags manually. The workflow rejects an existing release or a tag that points to another commit, builds from the exact dispatched `main` commit on an Apple Silicon `macos-26` runner, then creates the annotated tag without force and publishes the disk image, checksum, and generated `mactivate.rb` cask. The repository's release-tag ruleset blocks updates and deletions of `v*` tags after creation.

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

For each release, download its generated cask into the tap, then review and publish it:

```bash
tap="$(brew --repository HarshitBadam/mactivate)"
mkdir -p "$tap/Casks"
gh release download v1.0.1 \
  --repo HarshitBadam/mactivate \
  --pattern mactivate.rb \
  --clobber \
  --dir "$tap/Casks"
git -C "$tap" add Casks/mactivate.rb
git -C "$tap" commit -m "Update Mactivate to 1.0.1"
git -C "$tap" push
```

Users can then install directly:

```bash
brew tap HarshitBadam/mactivate
brew trust --cask HarshitBadam/mactivate/mactivate
brew install --cask mactivate
```

Homebrew requires users to explicitly trust casks from non-official taps. The cask stays outside the official `homebrew/cask` repository because the free build is not notarized.
