# Mactivate

Mactivate is a personal macOS hardware experiment that turns a MacBook's hidden sensors into shortcuts. It is built for daily use by me and friends, as a GitHub portfolio project, and as reusable sensor-engineering work for future projects.

This README is the single source of truth for product scope. Files under `docs/` preserve research evidence; they do not define the product.

## MVP contract

1. Moving a hand near the camera/notch sensor area opens a notch-attached dropdown panel.
2. Comfortable single, double, and triple taps on the MacBook palm rests trigger configured actions.
3. The panel offers a small set of useful quick actions.
4. A menu-bar/app icon always provides a reliable way to open the panel when hover sensing is unavailable or disabled.

The hover trigger is best-effort. It may be limited by lighting conditions, but it only opens the panel—it never executes an action. Tap recognition fails closed when input is ambiguous.

## Current status

The complete MVP stack is implemented. The sensor layer provides macOS SPU/ALS acquisition, safe property restoration, deterministic capture/replay, bounded-live palm-tap classification, and a best-effort ALS panel-open hint. `MactivateRuntime` starts the two sensor paths independently, maps accepted tap counts to persisted opaque action identifiers, emits action/panel intents, reports partial availability, and recreates sources safely across sleep and wake.

`MactivateApp` is the native menu-bar host. It presents one notch-attached or top-center fallback panel from either an ambient-light hint or the reliable status icon, exposes four configurable quick-action slots and single/double/triple mappings, and resolves only a deliberately safe action set: show the panel, open an application, open an HTTP(S) URL, or run a macOS Shortcut. Settings, first-run onboarding, diagnostics, accessibility behavior, and launch at login are included.

Validated on a **Mac14,2 MacBook Air M2 running macOS 26.2**:

- The SPU accelerometer is readable without root in an interactive user session at up to approximately 800 Hz.
- The ambient-light sensor exposes an unprivileged live `CurrentLux` value at 5 Hz, raisable to a measured 10 Hz ceiling.
- Palm-rest taps are materially easier to distinguish from typing and trackpad activity than nearby-table taps.
- Nearby-table taps are detectable, but overlap heavily with typing and desk bumps; they are not part of the MVP.
- ALS hover sensing works in favorable lighting, but dim light and ordinary moving shadows can make it unavailable or trigger false positives. The app-icon fallback is therefore part of the core experience.
- Live hardware smoke checks measured approximately 796 Hz accelerometer delivery and repeatable source lifecycle on the target machine.

Detailed measurements are in the [Mac14,2 probe results](docs/probe-results/2026-07-24-mac14-2-discovery.md).

## Repository

- `[MactuationCore](MactuationCore/)` — one Swift package containing the hardware-independent `MactuationCore` product and reusable macOS `MactuationHardware` product. Core owns models, source lifecycle events, capture/replay, deterministic classifiers, and committed regression fixtures; Hardware owns IOKit acquisition.
- `[MactivateRuntime](MactivateRuntime/)` — product-specific, intent-only runtime composition, persisted tap bindings, partial feature state, deduplication, and sleep/wake lifecycle handling.
- `[MactivateApp](MactivateApp/)` — AppKit/SwiftUI menu-bar app, notch/floating panel, settings and onboarding, safe action catalog, launch-at-login integration, and app-layer tests.
- `[MactuationProbe](MactuationProbe/)` — thin macOS CLI for machine identification, hardware discovery, capture, raw ALS observation, live tap diagnostics, and panel-hint diagnostics.
- `[scripts](scripts/)` — offline IMU analysis, rule scoring, and daemon-context diagnostics.
- `[docs/research](docs/research/)` — prior art, sensor landscape, and recorded gesture experiments.
- `[docs/probe-results](docs/probe-results/)` — measurements from physical hardware.



## Practical quality bar

Personal project does not mean careless software:

- Sensor processing and actions stay off the main thread.
- Ambiguous taps do nothing.
- One accepted tap sequence executes at most one action.
- Hover false positives may open the panel but cannot run an action.
- Sensor state is restored when capture stops.
- IMU and ALS failures are isolated so either feature can continue alone.
- Corrupt or unsupported runtime settings are preserved but fail closed.
- Sleep, stop, and source restarts reject stale callbacks and unresolved taps.
- Unsupported hardware and poor lighting degrade to the app-icon path instead of crashing.
- Core signal-processing behavior remains deterministic and tested.
- Hardware and environmental limitations are documented honestly.

Commercial qualification, broad model support, perfect detection in every environment, App Store distribution, and enterprise-grade migration or observability systems are not MVP requirements.

## Non-goals

- Nearby-table taps.
- Left/right/center tap localization or separate mappings by palm-rest side.
- Cross-region sequences, arbitrary rhythms, lid, pickup, tilt, or shake gestures.
- Camera or microphone fallback for the first version.
- Universal Mac compatibility.



## Build and test

```bash
swift test --package-path MactuationCore
swift test --package-path MactivateRuntime
swift build --package-path MactuationProbe
xcodebuild -project MactivateApp/MactivateApp.xcodeproj \
  -scheme MactivateApp -destination 'platform=macOS' test
```

Run the app from Xcode with the shared `MactivateApp` scheme. The target is an
`LSUIElement` menu-bar agent, so the hand icon—not a Dock tile—is the dependable
manual entry point.

Probe commands:

```bash
MactuationProbe/.build/debug/mactuation-probe identify
MactuationProbe/.build/debug/mactuation-probe discover
MactuationProbe/.build/debug/mactuation-probe als-watch --panel-hints
MactuationProbe/.build/debug/mactuation-probe tap-watch --rate-hz 800
MactuationProbe/.build/debug/mactuation-probe imu-capture --label test --rate-hz 800
```



## Next

1. Complete repeated daily-use qualification on Mac14,2 across bright/dim rooms, Spaces, fullscreen, external displays, and sleep/wake.
2. Add a polished application icon and capture final README screenshots.
3. Decide whether friend distribution warrants Developer ID signing, notarization, and a DMG; these are intentionally outside the MVP.
4. Collect evidence on additional Mac models before claiming broader compatibility.



## Research

- [Probe results](docs/probe-results/2026-07-24-mac14-2-discovery.md)
- [Gesture experiments and verdicts](docs/research/gesture-hypotheses.md)
- [Sensor landscape](docs/research/sensor-landscape.md)
- [Prior art](docs/research/prior-art.md)



## License

[MIT](LICENSE).