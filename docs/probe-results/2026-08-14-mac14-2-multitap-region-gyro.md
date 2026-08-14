# Probe Result — 2026-08-14 — Mac14,2 Multi-Tap Region Gyroscope

This record covers the gyro-based left/right multi-tap study that followed the 2026-07-24 accelerometer-only per-tap region refutation. It is research evidence from one user and machine, not a universal calibration.

## Environment

- Hardware: Mac14,2 MacBook Air, Apple M2
- OS: macOS 26.2
- Participants: one user
- Gesture set: natural left/right double and triple palm-rest taps
- Acquisition: SPU accelerometer and gyroscope, both approximately 798 Hz

## Protocol

The guided probe displayed one randomized side/pattern target at a time and waited indefinitely for a resolved gesture. A wrong detected count retried the same target. Each capture contained 40 gestures and 100 detected impacts: 10 gestures for each of left-double, left-triple, right-double, and right-triple.

- Training: `captures/20260814-030157-region-multitap-pilot`
- Independent transfer validation: `captures/20260814-031042-region-multitap-pilot`
- Between captures, the Mac was lifted and independently repositioned on the same hard table.
- Feature and thresholds were fitted from training only, then frozen before validation. Validation was not used to refit them.

Commands:

```bash
sudo ./MactuationProbe/.build/debug/mactuation-probe \
  region-multitap-capture --count 10 --rate-hz 800 --seed 20260814

sudo ./MactuationProbe/.build/debug/mactuation-probe \
  region-multitap-capture --count 10 --rate-hz 800 --seed 314159

./MactuationProbe/.build/debug/mactuation-probe region-multitap-analyze \
  --training captures/20260814-030157-region-multitap-pilot \
  --validation captures/20260814-031042-region-multitap-pilot
```

## Result

All five training folds selected `gyro_x_peak_balance_deg_s`. This feature is the sum of the baseline-corrected positive and negative gyroscope X extrema within ±50 ms of an accelerometer member peak.

Frozen transfer to the independently repositioned validation capture:

- First-member aggregation: 40/40 correct, zero unknown, zero wrong.
- Mean-member aggregation: 40/40 correct, zero unknown, zero wrong.
- Median-member aggregation: 40/40 correct, zero unknown, zero wrong.
- Majority vote: 39/40 classified, one unknown, zero wrong.
- Unanimous vote: 37/40 classified, three unknown, zero wrong.

The accepted production strategy is median member aggregation. It uses all resolved members, transferred perfectly in this pair, and avoided the validation coverage loss observed with voting.

## Verdict and scope

The distinct hypothesis is validated on this machine and user: natural double/triple motion contains a stable left/right signal in median `gyro_x_peak_balance_deg_s`. This does not reverse the 2026-07-24 result that accelerometer-only, per-tap X impulse was insufficient; the studies test different sensors and gesture units.

Product scope therefore includes exactly four assignable gestures: left/right double and left/right triple. Single taps remain detectable only for diagnostics and cannot run actions. Side classification requires per-user calibration with a guard band, and missing, stale, or ambiguous gyro data must return unknown and dispatch nothing.

## Limits

The evidence is two same-day captures from one user on one Mac14,2 / M2 running macOS 26.2, with one table and two placements. It does not establish cross-user, cross-model, long-duration, or broad environmental performance. Production release still requires calibrated per-side precision of at least 95%, per-side/pattern coverage of at least 90%, and zero dispatches for unknown or unavailable gyro input.
