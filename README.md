# Mactivate

Mactivate uses the accelerometer, gyroscope, and ambient-light sensor built into Apple Silicon MacBooks to turn physical gestures into macOS controls. Double and triple taps on the left or right palm rest can trigger actions like launching an application, opening a web address, or running a Shortcut. Moving a hand near the camera can reveal the Notch Panel, a four-control surface attached to the notch.

> Compatibility: macOS 13+ on Apple Silicon MacBooks. Validated on a MacBook Air M2 running macOS 26.2.

## Install

Install Mactivate with Homebrew or from the release disk image.

### Homebrew

```bash
brew install --cask <cask-name>
```

### Disk image

Download the latest `.dmg` from [GitHub Releases](https://github.com/HarshitBadam/mactivate/releases), open it, and drag Mactivate into Applications.

Open Mactivate from Applications, complete tap and left/right calibration, then assign actions to the four supported gestures and four Notch Panel slots.

## Build from source

```bash
git clone https://github.com/HarshitBadam/mactivate.git
cd mactivate
open app/MactivateApp.xcodeproj
```

Run the shared `MactivateApp` scheme. Package and test commands are documented in the area READMEs below.

## Repository

- [app/](app/): Native menu-bar application, Notch Panel, Configuration Window, calibration, and app tests
- [packages/](packages/): Production sensor, hardware, and runtime Swift packages
- [research/](research/): Offline fitting, evaluation, capture, and hardware diagnostics
- [tools/](tools/): Analysis and repository maintenance utilities
- [docs/](docs/): Architecture and measured product validation

Start with the [system overview](docs/architecture/system-overview.md) for the runtime flow or [product validation](docs/validation/product-validation.md) for the evidence behind the interaction.