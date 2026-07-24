# Mactivate

Mactivate is a macOS proof of concept where moving a hand near the camera/notch opens a large notch-attached mapping workspace, and single, double, or triple taps on calibrated palm-rest or nearby-table regions run configurable shortcuts and actions. See [Product Vision](docs/product-vision.md) for the authoritative product scope.

Deterministic classification, measured reliability, exactly-once actions, graceful recovery, polished accessible UI/UX, and unsurprising camera/microphone privacy behavior are release requirements.

## Status

**Research, local-probe planning, and the hardware-independent engine core.** This repository holds project standards, an evidence-backed research survey, a plan for hardware probing that must run later on a physical Apple Silicon MacBook, and [`MactuationCore`](MactuationCore/) — the tested, transport-agnostic foundation of the Mactuation Engine (sample models, capability states, capture format, deterministic replay, mock streams). No hardware acquisition or classification code exists yet; sensor feasibility remains hypothesis until the probe runs.

## Mactuation Engine

The **Mactuation Engine** is the experimental subsystem that will discover, read, fuse, calibrate, and classify low-level hardware signals into hand-near and tap events. Its hardware-independent core lives in [`MactuationCore`](MactuationCore/); acquisition adapters and classifiers follow the probe. Ambient-light sensing is preferred over camera input for hand-near detection; accelerometer sensing is preferred over microphone input for taps. Camera and microphone remain fallbacks, but carry greater privacy cost and activate macOS's green/orange privacy indicators. The engine intentionally explores beyond documented public macOS APIs and remains isolated behind capability-detected adapters.

## Evidence status: prior art vs. locally validated

This project draws a hard line between two kinds of claims:

- **Source-backed prior art** — behavior demonstrated by external projects, documentation, or teardown notes and cited with a direct URL. It tells us something is *plausible*, on *some* hardware/OS, per *someone else's* report.
- **Locally validated hardware support** — behavior this project has itself confirmed on the specific target MacBook and macOS version, via the local probe plan.

As of now, **everything in this repository is source-backed prior art or hypothesis. Nothing has been locally validated**, because this work was initialized in a non-macOS cloud environment with no access to the target MacBook. See the [Decision Log](docs/decision-log.md).

## Documentation

- [Product Vision](docs/product-vision.md) — the intended experience, separated into deliberate choices, facts, hypotheses, and open questions.
- [Sensor Landscape](docs/research/sensor-landscape.md) — capability survey of sensors/interfaces with access methods, privileges, data rates, confidence, and sources.
- [Prior Art](docs/research/prior-art.md) — catalogue of relevant open-source and commercial projects and what each actually proves.
- [Gesture Hypotheses](docs/research/gesture-hypotheses.md) — concrete, falsifiable hypotheses for palm-rest/table taps and hand-near opening.
- [Local Probe Plan](docs/local-probe-plan.md) — the step-by-step hardware investigation to run on the target MacBook.
- [Architecture Options](docs/architecture-options.md) — in-process vs. helper vs. daemon trade-offs and a preliminary recommendation.
- [UX Exploration](docs/ux-exploration.md) — the large notch workspace, setup, calibration, mapping, and fallback behavior.
- [Decision Log](docs/decision-log.md) — the few decisions actually made so far.

## Next step

The immediate next task is **not** to write product code. It is to run the [Local Probe Plan](docs/local-probe-plan.md) on the physical target MacBook in Cursor Desktop: establish the exact hardware model and macOS version, discover the relevant IOKit services, determine which sensor paths and privileges are actually available, and capture the first labelled sensor samples. Those results are what will turn the hypotheses in this repository into validated (or invalidated) facts.

## License

[MIT](LICENSE).
