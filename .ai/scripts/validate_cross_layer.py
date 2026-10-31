#!/usr/bin/env python3
"""Lightweight cross-layer evidence validator.

This validator does not pretend to understand the entire repository. It checks that
required evidence artifacts are present and that they do not leave UNKNOWN markers.
Use it as a gate, not as a substitute for engineering review.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import sys

DEFAULT_PATTERNS = {
    "layer_matrix": ["LAYER_IMPACT", "Layer Impact Matrix"],
    "contract_delta": ["CONTRACT_DELTA", "Contract Delta"],
    "completion": ["COMPLETION_EVIDENCE", "Completion Evidence"],
}


def files_under(root: Path):
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".md", ".json", ".yaml", ".yml"}:
            yield p


def contains_unknown(p: Path) -> bool:
    try:
        text = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return False
    bad = ["UNKNOWN count: 1", "UNKNOWN count: 2", "UNKNOWN count: 3", "| UNKNOWN |", "Status: UNKNOWN"]
    return any(x in text for x in bad)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--evidence-dir", default=None, help="directory containing task evidence")
    ap.add_argument("--strict", action="store_true", help="require matrix + completion evidence")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    scan = Path(args.evidence_dir).resolve() if args.evidence_dir else root
    files = list(files_under(scan))

    found_matrix = [p for p in files if "LAYER_IMPACT" in p.name.upper() or "Layer Impact Matrix" in p.read_text(encoding="utf-8", errors="ignore")[:3000]]
    found_completion = [p for p in files if "COMPLETION_EVIDENCE" in p.name.upper() or "Completion Evidence" in p.read_text(encoding="utf-8", errors="ignore")[:3000]]
    unknown_files = [p for p in found_matrix if contains_unknown(p)]

    print(f"scan={scan}")
    print(f"layer_matrices={len(found_matrix)}")
    print(f"completion_evidence={len(found_completion)}")
    print(f"matrices_with_unknown={len(unknown_files)}")

    errors = []
    if args.strict and not found_matrix:
        errors.append("missing Layer Impact Matrix")
    if args.strict and not found_completion:
        errors.append("missing Completion Evidence")
    if unknown_files:
        errors.append("one or more Layer Impact Matrices still contain UNKNOWN")

    if errors:
        for e in errors:
            print("ERROR:", e)
        sys.exit(2)
    print("PASS")

if __name__ == "__main__":
    main()
