#!/usr/bin/env python3
"""Offline IMU tap analysis for recorded Mactuation captures.

Pure stdlib so it runs on any macOS python3. Usage:

    python3 tools/analysis/analyze_imu.py [--threshold G] [--skip-s N] <capture_dir> ...
    python3 tools/analysis/analyze_imu.py --markers <capture_dir> ...

For each capture it detrends the accelerometer stream with a moving-average
high-pass, prints amplitude statistics of the residual magnitude, and (with
--threshold) detects impact events with a refractory window and prints their
times, peaks, features (all events and first group members separately), and
grouping. --markers instead reads the session's labels.csv and reports the
mean raw (non-detrended) gravity vector over each marker span against a flat
reference — used for axis-orientation checks from marked tilt holds.
"""

import argparse
import sys

from imu_analysis import (
    DETREND_WINDOW_S,
    GROUP_GAP_S,
    REFRACTORY_S,
    describe,
    describe_markers,
    detect_events,
    detrended_magnitude,
    group_events,
    load_accel,
    load_labels,
    percentile,
    print_event_features,
    spectral_features,
)

__all__ = [
    "DETREND_WINDOW_S",
    "GROUP_GAP_S",
    "REFRACTORY_S",
    "describe",
    "describe_markers",
    "detect_events",
    "detrended_magnitude",
    "group_events",
    "load_accel",
    "load_labels",
    "percentile",
    "print_event_features",
    "spectral_features",
]


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
