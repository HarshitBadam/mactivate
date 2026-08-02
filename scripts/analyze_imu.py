#!/usr/bin/env python3
"""Offline IMU tap analysis (Local Probe Plan, Step 8).

Pure stdlib so it runs on any macOS python3. Usage:

    python3 scripts/analyze_imu.py [--threshold G] [--skip-s N] <capture_dir> ...
    python3 scripts/analyze_imu.py --markers <capture_dir> ...

For each capture it detrends the accelerometer stream with a moving-average
high-pass, prints amplitude statistics of the residual magnitude, and (with
--threshold) detects impact events with a refractory window and prints their
times, peaks, features (all events and first group members separately), and
grouping. --markers instead reads the session's labels.csv and reports the
mean raw (non-detrended) gravity vector over each marker span against a flat
reference — used for axis-orientation checks from marked tilt holds.
"""

import argparse
import csv
import math
import os
import sys

DETREND_WINDOW_S = 0.5
REFRACTORY_S = 0.15
GROUP_GAP_S = 1.0


def load_accel(capture_dir, skip_s=0.0):
    path = os.path.join(capture_dir, "spu_accelerometer.csv")
    rows = []
    with open(path, newline="") as handle:
        for row in csv.reader(handle):
            if not row or row[0].startswith("timestamp"):
                continue
            rows.append((float(row[0]), float(row[1]), float(row[2]), float(row[3])))
    if skip_s > 0 and rows:
        cutoff = rows[0][0] + skip_s
        rows = [r for r in rows if r[0] >= cutoff]
    return rows


def load_labels(capture_dir):
    """Parse labels.csv (t_start_s,t_end_s,label,repetition,intensity,notes)."""
    path = os.path.join(capture_dir, "labels.csv")
    spans = []
    with open(path, newline="") as handle:
        for row in csv.reader(handle):
            if not row or row[0].startswith("t_start"):
                continue
            spans.append({"start": float(row[0]), "end": float(row[1]),
                          "label": row[2], "repetition": int(row[3]),
                          "intensity": row[4] if len(row) > 4 else "",
                          "notes": row[5] if len(row) > 5 else ""})
    return spans


def detrended_magnitude(rows):
    """High-pass each axis by subtracting a centered moving average.

    Returns (times, magnitude, rate, per_axis_residuals) where
    per_axis_residuals is {axis_name: [signed residual per sample]}.
    """
    n = len(rows)
    times = [r[0] for r in rows]
    duration = times[-1] - times[0]
    rate = (n - 1) / duration if duration > 0 else 0.0
    half = max(1, int(DETREND_WINDOW_S * rate / 2))

    residual = [0.0] * n
    per_axis = {}
    for axis, name in ((1, "x"), (2, "y"), (3, "z")):
        values = [r[axis] for r in rows]
        prefix = [0.0]
        for v in values:
            prefix.append(prefix[-1] + v)
        signed = [0.0] * n
        for i in range(n):
            lo = max(0, i - half)
            hi = min(n, i + half + 1)
            mean = (prefix[hi] - prefix[lo]) / (hi - lo)
            signed[i] = values[i] - mean
            residual[i] += signed[i] ** 2
        per_axis[name] = signed
    return times, [math.sqrt(v) for v in residual], rate, per_axis


def percentile(sorted_values, p):
    if not sorted_values:
        return 0.0
    k = (len(sorted_values) - 1) * p / 100.0
    lo = int(math.floor(k))
    hi = min(lo + 1, len(sorted_values) - 1)
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (k - lo)


def spectral_features(magnitude, peak_idx, rate, pre_s=0.020, post_s=0.140):
    """Spectral centroid (Hz) and high-band energy fraction (>=150 Hz) of the
    Hann-windowed detrended magnitude around an event peak (direct DFT,
    stdlib-only). Added for the desk-vs-typing-vs-bump spectral test — the
    last untested H-TAP-DESK separator (probe plan Step 8 features)."""
    lo = max(0, peak_idx - int(pre_s * rate))
    hi = min(len(magnitude), peak_idx + int(post_s * rate) + 1)
    window = magnitude[lo:hi]
    n = len(window)
    if n < 8 or rate <= 0:
        return 0.0, 0.0
    mean = sum(window) / n
    hann = [(w - mean) * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)))
            for i, w in enumerate(window)]
    total = 0.0
    weighted = 0.0
    high = 0.0
    for k in range(1, n // 2):
        freq = k * rate / n
        re = sum(hann[i] * math.cos(2 * math.pi * k * i / n) for i in range(n))
        im = sum(hann[i] * math.sin(2 * math.pi * k * i / n) for i in range(n))
        power = re * re + im * im
        total += power
        weighted += power * freq
        if freq >= 150.0:
            high += power
    if total <= 0:
        return 0.0, 0.0
    return weighted / total, high / total


def detect_events(times, magnitude, threshold, rate, per_axis=None,
                  long_window_s=0.150, spectral=False):
    """Peaks above threshold with a refractory window.

    Returns (t, peak, rise_slope_g_per_s, decay_ms, axis_impulses,
    long_axis_impulses[, (centroid_hz, high_frac)]) per event. axis_impulses
    is the signed per-axis integral over a +/-25 ms window around the peak
    (impulse direction, robust against single-sample sign flips);
    long_axis_impulses integrates from 25 ms before the peak to
    `long_window_s` after it (the ~150 ms window prior art uses for lateral
    tap localization).
    """
    events = []
    i = 0
    n = len(times)
    refractory = max(1, int(REFRACTORY_S * rate))
    impulse_half = max(1, int(0.025 * rate))
    long_span = max(1, int(long_window_s * rate))
    while i < n:
        if magnitude[i] >= threshold:
            end = min(n, i + refractory)
            peak_idx = max(range(i, end), key=lambda j: magnitude[j])
            # Onset sharpness: rise from the last sub-half-threshold sample.
            onset = peak_idx
            while onset > 0 and magnitude[onset - 1] > threshold / 2:
                onset -= 1
            rise_s = max(times[peak_idx] - times[onset], 1.0 / rate if rate else 0.01)
            # Decay: time for the envelope to fall back below half-threshold.
            tail = peak_idx
            while tail < n - 1 and magnitude[tail + 1] > threshold / 2:
                tail += 1
            decay_ms = (times[tail] - times[peak_idx]) * 1000
            impulses = {}
            long_impulses = {}
            if per_axis:
                lo = max(0, peak_idx - impulse_half)
                hi = min(n, peak_idx + impulse_half + 1)
                long_hi = min(n, peak_idx + long_span + 1)
                for name, signed in per_axis.items():
                    impulses[name] = sum(signed[lo:hi]) / rate if rate else 0.0
                    long_impulses[name] = sum(signed[lo:long_hi]) / rate if rate else 0.0
            event = [times[peak_idx], magnitude[peak_idx],
                     magnitude[peak_idx] / rise_s, decay_ms, impulses,
                     long_impulses]
            if spectral:
                event.append(spectral_features(magnitude, peak_idx, rate))
            events.append(tuple(event))
            i = max(peak_idx + refractory, tail + 1)
        else:
            i += 1
    return events


def group_events(events):
    groups = []
    for event in events:
        if groups and event[0] - groups[-1][-1][0] <= GROUP_GAP_S:
            groups[-1].append(event)
        else:
            groups.append([event])
    return groups


def print_event_features(events, heading):
    if not events:
        return
    peaks = sorted(e[1] for e in events)
    slopes = sorted(e[2] for e in events)
    decays = sorted(e[3] for e in events)
    print(f"  {heading} (median [p10..p90], n={len(events)}):")
    print(f"    peak:  {percentile(peaks, 50):.4f} g  [{percentile(peaks, 10):.4f}..{percentile(peaks, 90):.4f}]")
    print(f"    rise:  {percentile(slopes, 50):.2f} g/s  [{percentile(slopes, 10):.2f}..{percentile(slopes, 90):.2f}]")
    print(f"    decay: {percentile(decays, 50):.0f} ms  [{percentile(decays, 10):.0f}..{percentile(decays, 90):.0f}]")
    for slot, suffix in ((4, ""), (5, " (150ms)")):
        for axis in ("x", "y", "z"):
            values = sorted(e[slot][axis] * 1000 for e in events if axis in e[slot])
            if values:
                positive = sum(1 for v in values if v > 0)
                print(f"    {axis}-impulse{suffix}: {percentile(values, 50):+.3f} mg*s  "
                      f"[{percentile(values, 10):+.3f}..{percentile(values, 90):+.3f}]  "
                      f"positive {positive}/{len(values)}")
    if len(events[0]) > 6:
        centroids = sorted(e[6][0] for e in events)
        highs = sorted(e[6][1] * 100 for e in events)
        print(f"    spectral centroid: {percentile(centroids, 50):.0f} Hz  "
              f"[{percentile(centroids, 10):.0f}..{percentile(centroids, 90):.0f}]")
        print(f"    energy >=150 Hz:   {percentile(highs, 50):.1f} %  "
              f"[{percentile(highs, 10):.1f}..{percentile(highs, 90):.1f}]")


def describe(capture_dir, threshold=None, skip_s=0.0, spectral=False):
    rows = load_accel(capture_dir, skip_s=skip_s)
    times, magnitude, rate, per_axis = detrended_magnitude(rows)
    ordered = sorted(magnitude)
    stats = {p: percentile(ordered, p) for p in (50, 95, 99, 99.9)}
    print(f"\n=== {os.path.basename(capture_dir)} ===")
    skipped = f"  (skipped first {skip_s:g} s)" if skip_s > 0 else ""
    print(f"samples: {len(rows)}  rate: {rate:.1f} Hz  duration: {times[-1] - times[0]:.1f} s{skipped}")
    print("residual |a| (g):  p50 {:.5f}  p95 {:.5f}  p99 {:.5f}  p99.9 {:.5f}  max {:.5f}"
          .format(stats[50], stats[95], stats[99], stats[99.9], max(magnitude)))
    if threshold is None:
        return max(magnitude)

    events = detect_events(times, magnitude, threshold, rate, per_axis,
                           spectral=spectral)
    print(f"events above {threshold:.4f} g (refractory {REFRACTORY_S*1000:.0f} ms): {len(events)}")
    groups = group_events(events)
    print_event_features(events, "event features")
    first_members = [group[0] for group in groups]
    if len(first_members) != len(events):
        print_event_features(first_members, "first-member features")
    for group_index, group in enumerate(groups, 1):
        summary = ", ".join(
            f"{e[0]:.2f}s peak={e[1]:.4f}g z25={e[4].get('z', 0.0) * 1000:+.3f} "
            f"lat25={(abs(e[4].get('x', 0.0)) + abs(e[4].get('y', 0.0))) * 1000:.3f} "
            f"decay={e[3]:.0f}ms"
            + (f" cen={e[6][0]:.0f}Hz hf={e[6][1] * 100:.0f}%" if len(e) > 6 else "")
            for e in group)
        print(f"  group {group_index} ({len(group)} event{'s' if len(group) != 1 else ''}): {summary}")
    return max(magnitude)


def describe_markers(capture_dir, settle_s=0.5, hold_s=3.0, flat_window=(1.0, 5.0)):
    """Mean raw (non-detrended) gravity vector over each labels.csv marker span.

    Each marker span is taken as [t_start + settle_s, t_start + hold_s]; the
    flat reference is the mean over `flat_window` seconds after capture start
    (the operator rests the machine flat before the first marked motion).
    """
    rows = load_accel(capture_dir)
    spans = load_labels(capture_dir)
    t0 = rows[0][0]

    def window_mean(lo, hi):
        window = [r for r in rows if lo <= r[0] <= hi]
        if not window:
            return None, 0
        n = len(window)
        return tuple(sum(r[axis] for r in window) / n for axis in (1, 2, 3)), n

    print(f"\n=== {os.path.basename(capture_dir)} (markers) ===")
    flat, flat_n = window_mean(t0 + flat_window[0], t0 + flat_window[1])
    print(f"flat reference (t={flat_window[0]:g}..{flat_window[1]:g} s, n={flat_n}): "
          f"x {flat[0]:+.5f}  y {flat[1]:+.5f}  z {flat[2]:+.5f} g")
    for span in spans:
        mean, n = window_mean(span["start"] + settle_s, span["start"] + hold_s)
        if mean is None:
            print(f"marker {span['repetition']} at {span['start']:.2f} s: no samples in window")
            continue
        delta = tuple(mean[i] - flat[i] for i in range(3))
        tilt_deg = math.degrees(math.asin(min(1.0, math.hypot(delta[0], delta[1]))))
        print(f"marker {span['repetition']} at {span['start']:7.2f} s (n={n}): "
              f"mean x {mean[0]:+.5f}  y {mean[1]:+.5f}  z {mean[2]:+.5f} g")
        print(f"    delta from flat: x {delta[0]:+.5f}  y {delta[1]:+.5f}  z {delta[2]:+.5f} g"
              f"  (lateral tilt ~{tilt_deg:.1f} deg)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=float, default=None,
                        help="event threshold in g of detrended magnitude")
    parser.add_argument("--skip-s", type=float, default=0.0,
                        help="ignore the first N seconds (e.g. launch-keystroke transient)")
    parser.add_argument("--markers", action="store_true",
                        help="report mean raw gravity vector over each labels.csv span "
                             "instead of event analysis")
    parser.add_argument("--spectral", action="store_true",
                        help="add per-event spectral centroid and >=150 Hz energy "
                             "fraction (~160 ms Hann window around each peak)")
    parser.add_argument("captures", nargs="+")
    args = parser.parse_args()
    for capture in args.captures:
        if args.markers:
            describe_markers(capture)
        else:
            describe(capture, args.threshold, skip_s=args.skip_s,
                     spectral=args.spectral)


if __name__ == "__main__":
    sys.exit(main())
