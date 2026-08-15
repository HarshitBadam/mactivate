import math
import os

from .events import REFRACTORY_S, detect_events, group_events
from .io import load_accel, load_labels
from .signal import detrended_magnitude, percentile


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
