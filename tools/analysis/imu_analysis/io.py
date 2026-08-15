import csv
import os


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
