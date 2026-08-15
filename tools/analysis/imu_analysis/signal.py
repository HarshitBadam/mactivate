import math

DETREND_WINDOW_S = 0.5


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
    Hann-windowed detrended magnitude around an event peak (direct DFT).
    Window defaults match the measured desk-vs-typing-vs-bump spectral test."""
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
