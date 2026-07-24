# Gesture Hypotheses

Concrete, falsifiable hypotheses for the physical inputs Mactivate wants to recognize. Each has an explicit **failure criterion** — the local evidence that would kill or force a rethink of the hypothesis. This exists so the [Local Probe Plan](../local-probe-plan.md) collects data that can actually settle these questions, rather than confirming what we hoped.

**Nothing here is validated.** Confidence reflects strength of external prior art, not local measurement.

## Current product boundary

The product currently recognizes only:

- a hand approaching the camera/notch area to open the workspace; and
- single, double, or triple taps on calibrated MacBook palm-rest and nearby-table regions.

Cross-region sequences, arbitrary rhythms, lid gestures, and device movement/orientation gestures are out of scope. Ambient-light sensing is preferred over camera input for hand-near detection, and accelerometer sensing is preferred over microphone input for taps. Camera and microphone paths remain acceptable fallbacks because reliability is not yet proven, but they carry greater privacy cost and activate macOS's green/orange privacy indicators.

## Shared assumptions (must hold, or the preferred tap path weakens)

- **A1:** The SPU accelerometer is present and readable on the target MacBook at ~100 Hz (decimated). *Confidence: Confirmed-external for M2–M5 MacBooks; unverified on target.*
- **A2:** ~100 Hz is sufficient to separate closely-spaced taps (double/triple) and to characterize a tap's onset. *Confidence: Reported (Tapify, section9-lab, Knock all classify multi-tap at ~100 Hz).*
- **A3:** Typing and trackpad clicks are the dominant false-positive sources and have a distinguishable signature from deliberate taps. *Confidence: Hypothesis, supported by tapcut's "rhythm not a bump" framing and Haptyk proving typing is strongly visible.*

Common signal-processing toolkit available from prior art: gravity removal (Kalman/high-pass), band-pass filtering, magnitude, onset detection (dual-EMA fast/slow ratio, STA/LTA, CUSUM), peak detection, timing-window grouping, and confidence scoring. See [Prior Art](prior-art.md).

## Determinism and reliability gates

- Replaying identical recorded samples with identical versioned calibration and classifier settings must produce identical classified events.
- Single/double/triple resolution uses an explicit timing state machine. An action fires only after the configured sequence window resolves, so a single tap cannot fire and then be reinterpreted as a double tap.
- Every accepted event has one stable region, tap count, timestamp, confidence, and event ID; action dispatch deduplicates by event ID.
- Ambiguous, overlapping, stale, or low-confidence candidates are rejected rather than guessed.
- The initial probe explores feasibility. Product qualification additionally requires repeated sessions and at least 100 labelled attempts per supported tap count/region and hand-near condition.
- Minimum qualification targets are ≥95% deliberate-input recall, ≥99% precision, and zero unintended action firings during an eight-hour representative idle/typing/trackpad/bump run. Results are reported per hardware model, surface, sensor path, and lighting condition rather than averaged into a misleading global score.
- Sleep/wake, relaunch, temporary sensor loss, helper restart, and configuration reload must not create synthetic events or duplicate the last event.

---

## H-TAP-PALM — Single / double / triple palm-rest tap

- **Statement:** A finger tap on the palm-rest area produces a mechanical transient the SPU accelerometer can detect and, via inter-onset timing, classify into single/double/triple with usable reliability for one calibrated user.
- **Possible signal sources:** SPU accelerometer (preferred); SPU gyroscope (secondary, small rotational component); microphone only as fallback or fusion if mechanical sensing is insufficient.
- **Expected data signature:** short, sharp spike in gravity-removed acceleration magnitude (~5–50 ms onset), rapid decay to noise floor; amplitude in the ~0.005–0.05 g band (light→hard per section9-lab/Tapify). Multi-tap = 2–3 spikes within a ~450–1200 ms window, separated by more than a ~100–150 ms lockout.
- **Calibration needs:** per-user, per-machine amplitude/threshold or adaptive dual-EMA ratio; lockout duration; double/triple max-gap window; noise-floor baseline captured at rest.
- **Possible classifier direction:** start with dual-EMA onset ratio (no fixed amplitude threshold, per section9-lab) + timing-window grouping; escalate to a small feature-based classifier (onset sharpness, peak amplitude, decay time, spectral centroid) only if the simple detector confuses taps with typing.
- **Confidence:** Reported (multiple shipping apps do palm/chassis taps).
- **Fails if (local evidence):**
  - The at-rest noise floor overlaps the light-tap band such that no threshold separates them without unacceptable misses/false-fires (target to define, e.g. >20% miss at <5% false-fire).
  - Typing bursts are indistinguishable from double/triple taps in the collected data.
  - ~100 Hz cannot resolve fast double taps (onsets merge).

## H-TAP-DESK — Single / double / triple desk tap

- **Statement:** A tap on the desk *near* the MacBook couples into the chassis strongly enough for the SPU accelerometer (and/or microphone) to detect, and can be distinguished from a palm-rest tap.
- **Possible signal sources:** SPU accelerometer (preferred); gyroscope; microphone only as fallback or fusion if chassis coupling is insufficient.
- **Expected data signature:** transient similar to palm tap but (hypothesis) **lower mechanical amplitude and different spectral content** because energy travels desk→feet→chassis rather than directly into the palm-rest; likely **stronger relative acoustic signal**. Distance/surface-material dependent.
- **Calibration needs:** separate amplitude/threshold profile per desk surface; explicit "desk tap" labelled set at a fixed distance; comparison against palm-rest set and no-input baseline.
- **Possible classifier direction:** first attempt accelerometer-based palm-vs.-table discrimination using amplitude and spectral features; consider microphone fusion only if the preferred path cannot meet reliability goals.
- **Confidence:** Hypothesis (Knock's "desk mode" exists but via an iPhone on the desk, not chassis coupling; chassis-coupled desk taps are less proven).
- **Fails if (local evidence):**
  - Desk taps at a normal distance do not rise above the chassis noise floor on the accelerometer, and the microphone alone cannot carry the classification reliably.
  - The palm-tap and desk-tap feature distributions overlap so heavily that a per-user classifier cannot separate them above chance + margin.

## H-TAP-REGION — Left / right / center palm-rest localization

- **Statement:** The lateral position of a palm-rest tap (at minimum left vs. right of the trackpad) is recoverable from the SPU accelerometer, primarily from the sign and magnitude of the X-axis impulse, well enough to support calibrated per-region mappings.
- **Possible signal sources:** SPU accelerometer X-axis impulse (per knocker); gyroscope rotational transient as a secondary feature.
- **Expected data signature:** the tap transient's X-axis integral over a ~150 ms window has opposite sign for left vs. right taps and near-zero magnitude for center taps; sign orientation and thresholds vary per model/IMU placement, so calibration must establish them per machine.
- **Calibration needs:** per-machine `flip_x`-style orientation, lateral magnitude threshold, and labelled left/right/center takes; region boundaries defined during calibration, not assumed.
- **Possible classifier direction:** windowed per-axis impulse features on top of the H-TAP-PALM onset detector; escalate to 2–3 axis features only if X alone cannot separate the calibrated regions.
- **Confidence:** Reported (knocker demonstrates left/right/center on the same sensor path; unvalidated locally, and finer-than-three-region resolution is unproven anywhere).
- **Fails if (local evidence):**
  - Left/right labelled takes do not show a consistent X-impulse sign separation on the target machine.
  - The lateral signal varies so much with tap strength/position that calibrated thresholds cannot hold across a session.
  - Only a region count of 1 (no localization) survives the data — in which case the product's region mapping must be rethought (single region per surface, or desk vs. palm only).

## H-HAND-NEAR — Top-display hand-near / cover gesture

- **Statement:** Moving a hand toward or over the top-display / camera / notch area changes the ambient-light sensor reading enough, and fast enough, to open the large notch workspace.
- **Possible signal sources:** ALS via SPU HID (higher rate, root) or DisplayServices `AggregatedLux` (lower rate, unprivileged) are preferred. Camera input is an acceptable fallback if ALS is not viable, with explicit consent and macOS's green privacy indicator.
- **Expected data signature:** a downward step in lux (shadow) as the hand approaches, recovering when it leaves; magnitude depends on ambient brightness and hand distance. A deliberate "cover" should be a larger, faster drop than natural lighting drift.
- **Calibration needs:** ambient baseline and its natural drift rate; per-environment delta threshold; debounce to reject flicker; possibly rate-of-change rather than absolute level.
- **Possible classifier direction:** rate-of-change / step detector on lux with hysteresis; adaptive baseline to track slow ambient changes; require a minimum drop magnitude *and* slope.
- **Confidence:** Hypothesis, with placement now supported: teardown evidence puts the ALS inside the notch, immediately left of the camera (see [Sensor Landscape](sensor-landscape.md#ambient-light--physical-placement)), so a hand over the notch should shadow it. Update rate and shadow response remain unproven and still decide viability.
- **Fails if (local evidence):**
  - ALS update rate is too slow (e.g. seconds) to feel responsive — likely fatal for the SPU path if it only snapshots, and for the DisplayServices path which is brightness-smoothed.
  - The sensor's physical location makes a hand near the *notch* not meaningfully shadow it.
  - Natural lighting variation produces drops comparable to a deliberate hand cover, making false positives unavoidable.

## What the probe must produce to settle these

For every hypothesis above, the [Local Probe Plan](../local-probe-plan.md) must yield, at minimum: a **no-input baseline** recording, **labelled positive** recordings (per gesture, per intensity), and a **known false-positive** recording (sustained typing, trackpad use, being bumped). Without all three, "it detected my tap" is not evidence — it cannot distinguish a working detector from one that fires on everything.
