#!/usr/bin/env python3
"""Generate a diagnostic screenshot diff for UI verification.

This script is intentionally simple: it detects raster differences and produces
artifacts for human/AI visual review. It is NOT a universal pass/fail oracle.

Usage:
  python .ai/scripts/visual_diff.py prototype.png production.png --out-dir out
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

try:
    from PIL import Image, ImageChops, ImageEnhance
except ImportError:
    print("ERROR: Pillow is required for visual_diff.py. Install with: pip install pillow", file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("prototype")
    ap.add_argument("production")
    ap.add_argument("--out-dir", default="visual-diff-output")
    args = ap.parse_args()

    a_path = Path(args.prototype)
    b_path = Path(args.production)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    a = Image.open(a_path).convert("RGBA")
    b = Image.open(b_path).convert("RGBA")

    report = {
        "prototype": str(a_path),
        "production": str(b_path),
        "prototype_size": list(a.size),
        "production_size": list(b.size),
        "dimensions_match": a.size == b.size,
    }

    if a.size != b.size:
        report.update({
            "changed_pixel_ratio": None,
            "diff_bbox": None,
            "note": "Image dimensions differ. Geometry/environment mismatch must be resolved before pixel diagnostics are meaningful.",
        })
        (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 1

    diff = ImageChops.difference(a, b)
    # Collapse RGBA difference into luminance-like grayscale for counting.
    gray = diff.convert("L")
    hist = gray.histogram()
    total = a.size[0] * a.size[1]
    same = hist[0]
    changed = total - same
    ratio = changed / total if total else 0.0
    bbox = diff.getbbox()

    # Exaggerated diagnostic diff image.
    enhanced = ImageEnhance.Contrast(diff.convert("RGB")).enhance(4.0)
    enhanced.save(out / "diff.png")

    # 50/50 overlay helps spot displacement/proportion errors.
    overlay = Image.blend(a.convert("RGB"), b.convert("RGB"), 0.5)
    overlay.save(out / "overlay.png")

    report.update({
        "changed_pixels": changed,
        "total_pixels": total,
        "changed_pixel_ratio": ratio,
        "diff_bbox": list(bbox) if bbox else None,
        "note": "Raster ratio is diagnostic only; antialiasing/font rendering can produce harmless differences. Use AI/human visual review for acceptance.",
    })
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
