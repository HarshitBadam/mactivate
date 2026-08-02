# Local Probe Plan

A step-by-step hardware investigation to run **later, on the physical target MacBook**. Its job is to convert the hypotheses and source-backed claims in this repository into **locally validated facts (or refutations)** about *this specific machine and macOS version*.

> No step here has been executed and no result has been obtained. Do not record any result below as observed until it has actually run on the target MacBook. This document describes the probe work; it deliberately contains **no probe code** — implementation follows local validation.

## Preconditions

Before starting, confirm all of the following, and **stop** if any is false:

- [ ] Running on the physical target MacBook (Apple Silicon), not a VM, not a remote/cloud host.
- [ ] The operator can grant `sudo` (IOKit HID access to the SPU device requires root, per all prior art).
- [ ] The operator can grant TCC permissions if an optional fallback is tested (Microphone or Camera), and later for actions (Accessibility/Screen Recording).
- [ ] It is acceptable to briefly run small, inspectable read-only diagnostics. Nothing here writes to hardware or changes system state beyond temporarily lowering a sensor `ReportInterval`, which is restored.

## Safety and scope notes

- Read-only discovery first (`ioreg`, `system_profiler`, `sw_vers`); only then live capture.
- The one state change contemplated is temporarily setting a sensor `ReportInterval`/reporting/power state to receive reports; always restore defaults afterward (prior art restores `ReportInterval` to `5428500`).
- No kernel extensions, no writes to sensor registers beyond documented wake properties, no firmware interaction.

---

## Step 1 — Establish hardware model and macOS version

**Goal:** an exact, quotable identity for every result recorded.

Capture and record:
- Model identifier and marketing name (e.g. `Mac15,3`) and chip (e.g. M3 Pro): `sysctl hw.model machdep.cpu.brand_string`; `system_profiler SPHardwareDataType`.
- macOS version and build: `sw_vers`.
- Whether the built-in display has a notch (drives UI branch): note physically, and later cross-check with `NSScreen.safeAreaInsets`.

**Record into:** the Result Template §"Environment".

## Step 2 — Discover IOKit services / devices

**Goal:** determine which sensor interfaces physically exist before attempting to read them.

- Dump the registry and look for the SPU IMU device and its driver:
  - `ioreg -l -w0 | grep -A5 AppleSPUHIDDevice`
  - `ioreg -l -w0 | grep -A5 AppleSPUHIDDriver`
- Look for ambient-light service candidates:
  - SPU HID ALS: same `AppleSPUHIDDevice`, usage page `0xFF00`, usage `4`.
  - DisplayServices path: note whether `DisplayServicesClient`/`AggregatedLux` is reachable (validated later in code).
- Record, for each device found: registry path, `VendorID`, `ProductID`, `PrimaryUsagePage`, `PrimaryUsage`, `Transport`, and any `ReportInterval` default.

**Record into:** Result Template §"Discovered devices". **If `AppleSPUHIDDevice` is absent, the preferred accelerometer path for H-TAP-* is blocked on this machine — note it and continue with ALS before considering the microphone fallback.**

## Step 3 — Determine whether the SPU/HID paths are usable

**Goal:** move from "device exists in registry" to "device produces data".

For the SPU IMU:
- Confirm usages: accelerometer `0xFF00`/`3`, gyroscope `0xFF00`/`9`, ALS `0xFF00`/`4`.
- Note the exact report length and byte layout observed (prior art: 22-byte reports, int32 LE at offsets 6/10/14, ÷65536). **Verify offsets and scale locally — do not assume.**
- Note the wake sequence required (prior art: set `SensorPropertyReportingState`, `SensorPropertyPowerState`, `ReportInterval` on `AppleSPUHIDDriver`), and whether reports flow without it.
- Measure the **effective sample rate** actually delivered (target ~100 Hz decimated; confirm native-rate options).

For ALS: determine which path returns values, its update cadence, and whether lowering `ReportInterval` increases the rate.

**Record into:** Result Template §"Path verification".

## Step 4 — Identify privilege requirements

**Goal:** know exactly what each usable path costs in privilege, feeding [Architecture Options](architecture-options.md).

For each usable interface, determine empirically:
- Does read succeed **without** `sudo`? (Prior art: SPU IMU needs root; DisplayServices lux reportedly does not.)
- Does the public **CoreMotion** API report accelerometer availability (`CMMotionManager().isAccelerometerAvailable`)? Expected no on macOS per all prior art — but this is exactly the kind of "assumed unavailable" claim this plan exists to verify. If it ever works unprivileged, it is a public-API path that changes the architecture decision.
- Which TCC prompts appear if an optional fallback is tested (Microphone or Camera; none expected for IOKit HID)?
- Does access survive across app relaunch / reboot, or must privilege be re-granted?

**Record into:** Result Template §"Privileges".

## Step 5 — Capture raw sensor data

**Goal:** a clean, timestamped raw stream per usable sensor, for offline analysis.

The later probe tool should, for each sensor:
- Stream samples with a **hardware timestamp** where available (SPU reports carry `mach_absolute_time`-based timestamps per prior art), else a monotonic host clock.
- Record continuously to a file (see §Data format), with no on-the-fly classification — classification is done offline so the same raw data can be re-analyzed as hypotheses evolve.
- Log the effective sample rate and any dropped-report indications.

Capture a **≥30 s at-rest baseline** first (device untouched on a stable surface) as the reference noise floor.

## Step 6 — Collect labelled samples

**Goal:** the labelled dataset the [Gesture Hypotheses](research/gesture-hypotheses.md) require. For each gesture, capture multiple repetitions with a synchronized label (e.g. operator presses a marker key, or records start/stop times per take).

Minimum takes (single user, single machine; repeat per session/day to gauge stability):

| Label | Repetitions | Notes |
|---|---|---|
| `baseline_rest` | 1 × ≥30 s | untouched |
| `baseline_typing` | 1 × ≥30 s | sustained normal typing (key false positive) |
| `baseline_trackpad` | 1 × ≥30 s | clicks + scrolling |
| `baseline_bump` | 1 × ≥30 s | desk bumped, device shifted, adjusted |
| `palm_single` / `palm_double` / `palm_triple` | ≥30 each | fixed palm-rest spot |
| `palm_left` / `palm_right` / `palm_center` | ≥30 each | fixed spots left/right of trackpad and between (H-TAP-REGION; record spot positions in cm) |
| `palm_soft` / `palm_hard` | ≥30 each | intensity extremes |
| `desk_single` / `desk_double` / `desk_triple` | ≥30 each | fixed distance (record cm) + surface material |
| `hand_near` / `hand_cover` | ≥30 each | over the notch/top-display area; record ambient lux + light source |
Record contextual metadata per session: desk surface, ambient light level/source, whether on lap vs. desk, and time of day (thermal/lighting drift).

## Step 7 — Data format and storage expectations

- **One directory per capture session:** `captures/<yyyymmdd-hhmmss>-<label>/`.
- **Raw stream:** newline-delimited records or CSV — `timestamp_s, sensor, ax, ay, az[, gx, gy, gz]` for IMU and `timestamp_s, lux[, ch1..ch4]` for ALS. If the preferred tap path fails and microphone fallback is deliberately tested, store WAV or float32 PCM with a sidecar sample-rate header.
- **Label track:** a sidecar `labels.csv` — `t_start_s, t_end_s, label, repetition, intensity, notes`.
- **Session manifest:** a `session.json` capturing everything from the Result Template §Environment plus per-sensor effective rate and any anomalies.
- **Storage:** captures may be large and contain personal signals (e.g. BCG-adjacent heartbeat data). By default they are **git-ignored** (`captures/`). Only small, sanitized, deliberately-chosen samples should ever be committed, and only under `docs/`.
- **Reproducibility:** store the probe tool version/commit and the exact wake parameters used alongside each session.

## Step 8 — Compare palm-rest taps, desk taps, and the no-input baseline

**Goal:** decide whether the tap hypotheses survive, using the labelled data.

Offline analysis (no hardware needed once captured):
1. Gravity-remove and band-pass the IMU magnitude; compute per-onset features: peak amplitude, onset slope/sharpness, decay time, and dominant frequency / spectral centroid. Analyze acoustic RMS delta only in a separately consented fallback/fusion experiment after the accelerometer-only result is known.
2. Plot feature distributions for `palm_*`, `desk_*`, and each `baseline_*`.
3. Assess separability: Can a threshold or simple classifier separate taps from `baseline_typing`/`baseline_trackpad` at an acceptable operating point? Can palm vs. desk be separated? Do `palm_left`/`palm_right`/`palm_center` show a consistent X-impulse sign/magnitude separation (H-TAP-REGION)?
4. Report a confusion matrix and a chosen operating point (miss rate vs. false-fire rate) per gesture.

**A hypothesis passes only if its Gesture-Hypotheses failure criterion is *not* met in this data.**

## Step 9 — Test top-display ambient-light hand gestures

**Goal:** decide whether H-HAND-NEAR is viable *before* building any UI around it.

1. Establish the ALS **update cadence** on each usable path (SPU HID vs. DisplayServices). If the fastest usable cadence is slower than ~5–10 Hz, note that responsiveness is likely fatal and say so.
2. **Map sensor placement vs. shadow geometry.** Teardown evidence puts the ALS inside the notch, left of the camera — verify behaviorally: with fixed ambient light, cover each candidate area in turn (notch center, notch left/right ends, display center, top bezel corners, keyboard deck) and record which covers actually move the reading, and by how much. This settles whether "hand near the notch" shadows the sensor on this machine.
3. With a fixed ambient light, record `baseline` lux drift for ≥60 s, then `hand_near` and `hand_cover` takes at a fixed height over the notch.
4. Compute the lux drop magnitude and slope for deliberate covers vs. the natural drift band.
5. Repeat in ≥2 lighting conditions (bright room, dim room) — the signal is expected to scale with ambient brightness.
6. Decide: is there a drop magnitude + slope threshold that fires on deliberate covers but not on natural drift, at a responsive latency? Record the verdict against H-HAND-NEAR's failure criterion.
7. Test a consented camera fallback only if ALS is refuted or inconclusive; record its reliability separately along with the green privacy-indicator trade-off.

## Step 10 — Determinism and stability qualification

**Goal:** reject implementations that work in a demo but are not repeatable enough to run actions safely.

1. Replay every captured stream at least twice with the same versioned configuration and verify byte-for-byte identical classified event output.
2. Verify single/double/triple state-machine boundaries around the configured timing thresholds. Each accepted event must dispatch exactly once; ambiguous boundary cases must dispatch nothing.
3. Collect product-qualification data across repeated sessions: at least 100 labelled attempts per supported tap count/region and hand-near condition.
4. Run an eight-hour representative no-intent session containing idle time, typing, trackpad use, desk bumps, lighting changes, and normal background work. The target is zero unintended action firings.
5. Exercise relaunch, sleep/wake, screen changes, helper restart, sensor disconnect/reconnect, configuration reload, and permission revocation. None may synthesize or duplicate an event, hang the UI, or leave stale capability/privacy status.
6. Report recall and precision separately for every supported hardware model, region/surface, sensor path, and lighting condition. Minimum qualification targets are ≥95% recall and ≥99% precision; do not hide a failing condition in an aggregate.
7. If camera or microphone fallback is tested, verify it never starts without explicit opt-in, its in-app state agrees with the macOS privacy indicator, disabling it releases the device promptly, and raw media is not retained without separate capture consent.

---

## Result Template

Copy per probe session.

```
# Probe Result — <yyyy-mm-dd> — <operator>

## Environment
- Model identifier / chip:
- Marketing name:
- macOS version / build:
- Notch present (physical):
- Probe tool version / commit:

## Discovered devices
- AppleSPUHIDDevice present:            [yes/no]  path:
- AppleSPUHIDDriver present:            [yes/no]  path:
- ALS via SPU HID (0xFF00/4):           [yes/no]
- ALS via DisplayServices AggregatedLux:[yes/no]

## Path verification
- Accelerometer usage confirmed (0xFF00/3):   [yes/no]  report len:   offsets:   scale:
- Gyroscope usage confirmed (0xFF00/9):        [yes/no]
- Effective IMU sample rate (measured Hz):
- Wake sequence required:                      [yes/no]  properties set:
- ALS path used / cadence (Hz):

## Privileges
- SPU IMU readable without sudo:   [yes/no]
- ALS readable without sudo:       [yes/no]
- TCC prompts observed:            [list]
- Persistence across relaunch/reboot:

## Data captured
- Session dir(s):
- Sensors captured:
- Labels + repetitions:
- Anomalies / dropped reports:

## Hypothesis verdicts (this session)
- H-TAP-PALM:   [supported / refuted / inconclusive] — evidence:
- H-TAP-DESK:   [supported / refuted / inconclusive] — evidence:
- H-TAP-REGION: [supported / refuted / inconclusive] — evidence:
- H-HAND-NEAR:  [supported / refuted / inconclusive] — evidence:

## Quality gates
- Deterministic replay: [pass/fail] — event output hash(es):
- Exactly-once dispatch: [pass/fail]
- Recall / precision by condition:
- Eight-hour unintended action count:
- Lifecycle interruption matrix:
- Camera/microphone opt-in and release behavior:
```

## Failure-Report Template

Use when a step cannot complete (device absent, no data, permission denied, crash).

```
# Probe Failure — <yyyy-mm-dd> — <operator>

- Step / goal that failed:
- What was attempted (command / action, non-code description):
- Observed result (error text, empty stream, timeout, etc.):
- Environment (model / macOS / build):
- Privilege state at time of failure (sudo? TCC grants?):
- Hypotheses blocked by this failure:
- Suspected cause (labelled hypothesis vs. confirmed):
- Next diagnostic to try:
- Does this refute a source-backed claim in docs/? If so, which, and update the Decision Log.
```

---

## Handoff to implementation

Only after Steps 1–4 have a "usable path" result on the target hardware should any Mactuation Engine capture code be written, and only after Steps 5–9 produce labelled data should any classifier be committed — per the engineering rule *"build a sensor probe and labelled-data workflow before committing to gesture classifications."* A classifier is not product-ready until it passes Step 10. Feed every result back into [Gesture Hypotheses](research/gesture-hypotheses.md), [Sensor Landscape](research/sensor-landscape.md), and the [Decision Log](decision-log.md).
