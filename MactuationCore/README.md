# MactuationCore

The hardware-independent core of the Mactuation Engine: the parts that are required no matter which sensor paths survive the [Local Probe Plan](../docs/local-probe-plan.md), and that can be built and tested without the target MacBook.

## What is here

- **Sample models** (`SensorSample.swift`) — typed IMU/ALS samples keyed by `SensorPath`, where a path identifies the acquisition strategy (e.g. SPU HID ALS vs. DisplayServices ALS), not just the physical sensor.
- **Capability model** (`Capability.swift`) — per-path `unknown / available / unavailable / needsPrivilege / needsOptIn` states. Every real path defaults to `unknown`; only locally observed evidence may promote it.
- **Capture format** (`Capture/`) — the session directory layout from Probe Plan Step 7: one CSV stream per path, a `labels.csv` sidecar, and a `session.json` manifest recording environment, clock, effective rates, and acquisition parameters. Doubles are encoded round-trippably so replay of a written capture is exact.
- **Deterministic replay** (`Replay/`) — `ReplaySensorSource` re-delivers a capture in a fixed merged order with no wall-clock pacing, and `StreamDigest` fingerprints a sequence so identical replays can be asserted byte-for-byte (the project's deterministic-replay quality gate).
- **Mock source** (`MockSensorSource.swift`) — seeded synthetic streams shaped like the gesture-hypotheses signatures, for tests and offline pipeline work. Mock data is never a capability claim.

## What is deliberately absent

- IOKit/HID, DisplayServices, or any hardware acquisition code — those are probe deliverables, written on the physical target machine after Probe Steps 1–4 verify the paths.
- Gesture classifiers and thresholds — blocked until Probe Steps 5–9 produce labelled data.
- Camera/microphone capture — requires the explicit opt-in UX first.

Real adapters will implement `SensorSource`, the same boundary the mock and replay sources use, so everything downstream is already exercised.

## Building and testing

Foundation-only; builds and tests on macOS and Linux:

```bash
swift test
```
