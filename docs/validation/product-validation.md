# Product validation

The first study evaluated palm-rest taps and nearby desk taps as configurable input surfaces. The second tested whether completed palm-rest gestures could be classified as left or right.

> Scope: One user, one MacBook Air M2 identified as Mac14,2, macOS 26.2, and a small set of placements and environments.

## Hardware and tap study

`MactuationProbe`, Python analysis, and deterministic Swift replay were used with labelled palm taps, rest, typing, trackpad use, desk knocks, machine handling, room-light changes, and dim light.

### Sensor access

The sensor processing unit exposed accelerometer and gyroscope devices through `AppleSPUHIDDevice`. Accelerometer reports were 22 bytes and matched gravity after decoding.

The accelerometer delivered approximately 100 Hz at the initial setting and 800.8 Hz at the fastest advertised rate. Device access, wake properties, and sample delivery worked without elevation in an interactive user session. Core Motion reported no available accelerometer.

The ambient-light driver exposed `CurrentLux` without elevation at approximately 5 Hz, with a measured 10 Hz ceiling after an interval override.

### Palm-rest tap detection

At 800 Hz, palm-rest taps produced a vertical impulse pattern that differed from typing and trackpad clicks. Firm impacts and desk disturbances required separate firm-impact handling, aftershock suppression, and a lateral-motion veto.

The final discovery rule accepted between 72% and 100% of groups across the recorded palm-tap sets. After the lateral vetoes, replay accepted no groups from the recorded rest, typing, trackpad, desk-knock, or two independent disturbance baselines.

### Rejected paths

- Nearby desk taps were evaluated as a second configurable input surface. They overlapped typing and unrelated desk movement in amplitude, impulse, decay, and frequency.
- Accelerometer impulse did not reliably classify individual taps as left or right after axis orientation and tap strength were controlled.
- Notch Hover overlapped normal shadows and disappeared at the measured dim-light floor.

## Spatial tap study

Training and validation captures each contained 40 gestures with 10 left doubles, 10 left triples, 10 right doubles, and 10 right triples. The MacBook was lifted and repositioned between captures. Feature selection and thresholds used only the training capture.

- Training: `captures/20260814-030157-region-multitap-pilot`
- Validation: `captures/20260814-031042-region-multitap-pilot`

All five training folds selected `gyro_x_peak_balance_deg_s`, which measures the balance of gyroscope X movement around each tap.

First-member, mean-member, and median-member aggregation each classified all 40 validation gestures correctly. Majority vote classified 39 with one unknown. Unanimous vote classified 37 with three unknown. No strategy produced a wrong side.

Median aggregation was selected because it used every tap member and retained full coverage. Across both captures, the 120 gaps between taps ranged from 159.093 to 237.979 milliseconds. Spatial calibration uses a 300 millisecond grouping boundary.

---

## Product outcome

Mactivate supports left double, left triple, right double, and right triple gestures. Single taps remain diagnostic. Spatial gestures require personal calibration, and missing, stale, or near-boundary gyroscope data produces no action.

Notch Hover may open the Notch Panel but cannot run an action. The menu bar item provides manual access.

## Limits

The evidence does not establish support across all users or MacBook models.

Production qualification still requires at least 95% precision per side, at least 90% coverage per side and pattern, and no action dispatch when spatial input is unknown.