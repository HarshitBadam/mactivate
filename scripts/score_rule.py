#!/usr/bin/env python3
"""Score the validated H-TAP-PALM tiered rule per group, using analyze_imu.py's
exact pipeline (imported, not reimplemented). Companion to the Swift
TapClassifier: this is the ground-truth side of its parity fixtures.

Rule (docs/probe-results/2026-07-24-mac14-2-discovery.md, left-calibrated):
  accept a group iff it has <= 3 members and its FIRST member passes its
  amplitude-selected tier:
    comfort (peak < 0.25 g): z25 > 0 and lat25 < 0.25 mg*s
    firm (peak >= 0.25 g):   lat25/peak <= 5 (mg*s)/g and decay <= 150 ms

Usage: python3 scripts/score_rule.py <capture_dir> ...
Prints per capture: a verdict string (C=comfort accept, F=firm accept,
R=reject) over groups in time order, then per-group first-member features.
"""

import sys

import analyze_imu

THRESHOLD_G = 0.04
COMFORT_LATERAL_VETO_MGS = 0.25
FIRM_CUT_G = 0.25
FIRM_RATIO_MAX = 5.0
FIRM_DECAY_MAX_MS = 150.0


def judge(group):
    if len(group) > 3:
        return "R"
    t, peak, _rise, decay, impulses, _long = group[0][:6]
    z25 = impulses["z"] * 1000
    lat25 = (abs(impulses["x"]) + abs(impulses["y"])) * 1000
    if peak >= FIRM_CUT_G:
        if lat25 / peak <= FIRM_RATIO_MAX and decay <= FIRM_DECAY_MAX_MS:
            return "F"
        return "R"
    if z25 > 0 and lat25 < COMFORT_LATERAL_VETO_MGS:
        return "C"
    return "R"


def score(capture_dir):
    rows = analyze_imu.load_accel(capture_dir)
    times, magnitude, rate, per_axis = analyze_imu.detrended_magnitude(rows)
    events = analyze_imu.detect_events(times, magnitude, THRESHOLD_G, rate, per_axis)
    groups = analyze_imu.group_events(events)
    verdicts = "".join(judge(group) for group in groups)
    accepted = sum(1 for v in verdicts if v != "R")
    print(f"\n=== {capture_dir.rstrip('/').split('/')[-1]} ===")
    print(f"groups: {len(groups)}  accepted: {accepted}  verdicts: {verdicts or '(none)'}")
    for index, group in enumerate(groups, 1):
        t, peak, _rise, decay, impulses, _long = group[0][:6]
        z25 = impulses["z"] * 1000
        lat25 = (abs(impulses["x"]) + abs(impulses["y"])) * 1000
        print(f"  group {index} [{verdicts[index - 1]}] n={len(group)} t={t:.2f}s "
              f"peak={peak:.4f}g z25={z25:+.3f} lat25={lat25:.3f} decay={decay:.0f}ms")


def main():
    for capture in sys.argv[1:]:
        score(capture)


if __name__ == "__main__":
    main()
