# MactuationCore, MactuationHardware, MactuationCapture, and MactuationTestSupport

This Swift package exposes four library products:

- `MactuationCore` — hardware-independent models and deterministic signal processing, including the runtime-reachable region-probe qualification contract.
- `MactuationHardware` — reusable macOS IOKit acquisition adapters that depend on Core.
- `MactuationCapture` — non-shipping; the on-disk session capture/replay format. Depends only on Core.
- `MactuationTestSupport` — non-shipping; mock/replay sensor sources and deterministic stream digests for tests and offline pipeline work. Depends on Core and Capture.

All deterministic tests run without sensor access. Hardware access remains a guided smoke test on a supported Mac.

## What is here

- **Sample models** (`SensorSample.swift`) — typed IMU/ALS samples keyed by `SensorPath`, where a path identifies the acquisition strategy (e.g. SPU HID ALS vs. DisplayServices ALS), not just the physical sensor.
- **Capability model** (`Capability.swift`) — per-path `unknown / available / unavailable / needsPrivilege / needsOptIn` states. Every real path defaults to `unknown`; only locally observed evidence may promote it.
- **Deterministic sample ordering** (`Support/SensorSampleOrdering.swift`) — `[SensorSample].sortedDeterministically()` merges by timestamp, then path name, then original position, so ties never depend on sort stability. `MactuationCapture`'s `CaptureReader` and `MactuationTestSupport`'s `ReplaySensorSource`/`MockSensorSource` all merge through this one helper instead of each re-implementing the same tie-break.
- **Capture format** (`MactuationCapture`'s `Capture/`) — one CSV stream per path, a `labels.csv` sidecar, and a `session.json` manifest recording environment, privileges, discovered HID usages, compatibility, clock, effective rates, and acquisition parameters. Doubles are encoded round-trippably so replay of a written capture is exact.
- **Deterministic replay** (`MactuationTestSupport`'s `Replay/`) — `ReplaySensorSource` re-delivers a capture in a fixed merged order with no wall-clock pacing, and `StreamDigest` fingerprints a sequence so identical replays can be asserted byte-for-byte (the project's deterministic-replay quality gate).
- **Mock source** (`MactuationTestSupport`'s `Sensors/MockSensorSource.swift`) — seeded synthetic streams shaped like the gesture-hypotheses signatures, for tests and offline pipeline work. Mock data is never a capability claim.
- **Processing isolation** (`SensorProcessingQueue.swift`) — a serial, user-initiated queue for processing samples off the main thread in delivery order.
- **Source lifecycle** (`SensorSource.swift`) — one acquisition boundary for samples, asynchronous failures, completion, and restoration warnings.
- **Palm-tap classification** (`Classification/Tap/`) — deterministic batch and bounded-live accelerometer classifiers with versioned calibration, safe commit boundaries, explicit replay finalization, and single/double/triple palm-rest groups. Accelerometer acceptance alone cannot localize a tap to a side — `mac14_2SpatialMultiTap` is the timing base every personal `personal-spatial-` profile derives from, not a universal runtime fallback, and every user must complete calibration.
- **Spatial region classification** (`Classification/TapRegion/Runtime/`) — the production region stage that localizes left/right *after* an accelerometer-accepted double/triple group: it extracts the qualified gyro-X peak-balance feature at accepted member timestamps, aggregates members by median, and fails closed through a calibrated guard band. `TapRegionProbeAnalyzer.evaluate(predictions:observations:)` here is the shared scoring primitive production calibration uses; the broader offline threshold/linear/multi-tap fitting analyzers that build on it live in the research-only `MactuationResearch` package (`research/analysis/`).
- **ALS panel hint** (`Classification/AmbientLight/`) — a deterministic, versioned ambient-light dip detector with warm-up, dim-light, recovery, and cooldown behavior. It emits a non-actionable hint and does not claim to identify a hand.
- **Committed fixtures** (`Tests/MactuationCoreTests/Fixtures/`) — compact sanitized IMU/ALS regressions that run in a clean clone; the larger local capture library remains ignored.

## MactuationHardware

- `SPUIMUSource` owns its HID RunLoop thread, can deliver accelerometer and gyroscope samples, and restores each path's wake properties on shutdown.
- `RegistryALSSource` polls the live `CurrentLux` property and restores an optional report-interval override.
- `SPUHardwareInspector` provides discovery and measured capability state without exposing registry handles.
- Report decoding, invalid configuration, source lifecycle, and restoration behavior fail explicitly rather than being silently discarded.

`research/probe`'s `mactuation-probe` consumes `MactuationCore`, `MactuationHardware`,
`MactuationCapture`, and the research-only `MactuationResearch` package.
`MactivateRuntime` composes only `MactuationCore` and `MactuationHardware` into
product intents, and `MactivateApp` owns the notch UI and safe action dispatch.
Those product-specific layers intentionally remain outside this reusable package.

## Building and testing

```bash
swift test --package-path packages/core
swift test --package-path research/analysis
swift build --package-path research/probe
```

The validated hardware is a Mac14,2 MacBook Air M2. In one-user 2026-08-14 probe sessions, both IMU paths delivered at approximately 798 Hz and median aggregation of per-member `gyro_x_peak_balance_deg_s` transferred 40/40 left/right double/triple gestures to an independently repositioned capture. This is evidence for a production classifier, not a universal preset: callers must require per-user calibration and treat missing or ambiguous gyro classification as unknown.

ALS hints are unavailable near the measured dim-light floor and ordinary stationary shadows can produce false positives; callers must always provide manual panel access.
