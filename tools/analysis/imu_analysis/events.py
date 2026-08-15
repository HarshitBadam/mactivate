from .signal import spectral_features

REFRACTORY_S = 0.15
GROUP_GAP_S = 1.0


def detect_events(times, magnitude, threshold, rate, per_axis=None,
                  long_window_s=0.150, spectral=False):
    """Returns (t, peak, rise_slope_g_per_s, decay_ms, axis_impulses,
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
            onset = peak_idx
            while onset > 0 and magnitude[onset - 1] > threshold / 2:
                onset -= 1
            rise_s = max(times[peak_idx] - times[onset], 1.0 / rate if rate else 0.01)
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
