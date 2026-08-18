# Release runbook

Maintainer-only operational reference for running and recovering the Mactivate release pipeline. See [Distribution](distribution.md) for what the release path is and what it means for users; this document is about operating it.

## Automation credentials

Create a GitHub App installed only on `HarshitBadam/mactivate` and `HarshitBadam/homebrew-mactivate` with these repository permissions:

- Actions: read and write
- Contents: read and write
- Pull requests: read and write

Store its application ID as the `RELEASE_APP_ID` Actions secret and its private key as `RELEASE_APP_PRIVATE_KEY`. The short-lived installation token lets release pull requests trigger CI and lets publication open the cross-repository Homebrew pull request without a personal access token.

Protect `main` with pull requests and require the `Repository policy`, `Swift packages`, and `macOS application` checks. For a solo-maintained repository, required approvals can remain at zero while the checks stay mandatory.

Do not create, move, or delete release tags manually. The release-tag ruleset keeps published source and artifacts tied to one immutable commit.

## Recovery

If publication fails while the GitHub Release is still a draft, rerun it from the existing immutable tag:

```bash
gh workflow run release.yml --ref v<version> -f version=<version>
```

If only the Homebrew job fails after publication, run the current workflow in recovery mode. This preserves the published assets and repeats only downstream validation and delivery:

```bash
gh workflow run release.yml \
  --ref main \
  -f version=<version> \
  -f homebrew_only=true
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
