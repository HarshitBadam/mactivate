# MactuationCore and MactuationHardware

This Swift package exposes two focused library products:

- `MactuationCore` — hardware-independent models, replay, and deterministic signal processing.
- `MactuationHardware` — reusable macOS IOKit acquisition adapters that depend on Core.

All deterministic tests run without sensor access. Hardware access remains a guided smoke test on a supported Mac.

## What is here

- **Sample models** (`SensorSample.swift`) — typed IMU/ALS samples keyed by `SensorPath`, where a path identifies the acquisition strategy (e.g. SPU HID ALS vs. DisplayServices ALS), not just the physical sensor.
- **Capability model** (`Capability.swift`) — per-path `unknown / available / unavailable / needsPrivilege / needsOptIn` states. Every real path defaults to `unknown`; only locally observed evidence may promote it.
- **Capture format** (`Capture/`) — one CSV stream per path, a `labels.csv` sidecar, and a `session.json` manifest recording environment, privileges, discovered HID usages, compatibility, clock, effective rates, and acquisition parameters. Doubles are encoded round-trippably so replay of a written capture is exact.
- **Deterministic replay** (`Replay/`) — `ReplaySensorSource` re-delivers a capture in a fixed merged order with no wall-clock pacing, and `StreamDigest` fingerprints a sequence so identical replays can be asserted byte-for-byte (the project's deterministic-replay quality gate).
- **Mock source** (`MockSensorSource.swift`) — seeded synthetic streams shaped like the gesture-hypotheses signatures, for tests and offline pipeline work. Mock data is never a capability claim.
- **Processing isolation** (`SensorProcessingQueue.swift`) — a serial, user-initiated queue for processing samples off the main thread in delivery order.
- **Source lifecycle** (`SensorSource.swift`) — one acquisition boundary for samples, asynchronous failures, completion, and restoration warnings.
- **Palm-tap classification** (`Classification/`) — deterministic batch and bounded-live classifiers with versioned calibration, safe commit boundaries, explicit replay finalization, and single/double/triple palm-rest groups.
- **ALS panel hint** (`Classification/`) — a deterministic, versioned ambient-light dip detector with warm-up, dim-light, recovery, and cooldown behavior. It emits a non-actionable hint and does not claim to identify a hand.
- **Committed fixtures** (`Tests/MactuationCoreTests/Fixtures/`) — compact sanitized IMU/ALS regressions that run in a clean clone; the larger local capture library remains ignored.

## MactuationHardware

- `SPUIMUSource` owns its HID RunLoop thread, delivers accelerometer samples, and restores wake properties on shutdown.
- `RegistryALSSource` polls the live `CurrentLux` property and restores an optional report-interval override.
- `SPUHardwareInspector` provides discovery and measured capability state without exposing registry handles.
- Report decoding, invalid configuration, source lifecycle, and restoration behavior fail explicitly rather than being silently discarded.

`MactuationProbe` consumes both products. The future app-facing coordinator, notch UI, mappings, and action dispatch intentionally remain outside this package until the app provides a real consumer.

## Building and testing

```bash
swift test --package-path MactuationCore
swift build --package-path MactuationProbe
```

The validated hardware is a Mac14,2 MacBook Air M2. ALS hints are unavailable near the measured dim-light floor and ordinary stationary shadows can produce false positives; callers must always provide manual panel access.
