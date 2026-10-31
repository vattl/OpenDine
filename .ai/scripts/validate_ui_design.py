#!/usr/bin/env python3
"""Lightweight v3.6 UI design artifact validator.

This validates artifact presence/obvious unresolved markers; it does not pretend to judge design quality.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import sys

REQUIRED_FOR_REFACTOR = [
    "UI_DESIGN_STRATEGY.md",
    "LEGACY_UI_DECOMPOSITION.md",
    "COMPONENT_CAPABILITY_AUDIT.md",
    "PROTOTYPE_TECHNICAL_PLAN.md",
]
LOCK_FILES = [
    "UI_CONTENT_CONTRACT.md",
    "UI_ELEMENT_CONTRACT.md",
    "UI_LOCK_MANIFEST.md",
]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("path", nargs="?", default=".", help="UI work artifact directory")
    p.add_argument("--mode", choices=["refine", "refactor", "redesign"], default="refactor")
    p.add_argument("--locked", action="store_true")
    args = p.parse_args()

    root = Path(args.path)
    required = list(REQUIRED_FOR_REFACTOR if args.mode in {"refactor", "redesign"} else ["UI_DESIGN_STRATEGY.md"])
    if args.locked:
        required += LOCK_FILES

    missing = [name for name in required if not (root / name).exists()]
    unresolved = []
    for name in required:
        f = root / name
        if f.exists():
            text = f.read_text(encoding="utf-8", errors="ignore")
            if "TBD" in text or "UNKNOWN" in text:
                unresolved.append(name)

    if missing:
        print("UI DESIGN CHECK: FAIL")
        print("Missing:")
        for m in missing:
            print(f"- {m}")
        return 2

    print("UI DESIGN CHECK: PASS_WITH_WARNINGS" if unresolved else "UI DESIGN CHECK: PASS")
    if unresolved:
        print("Unresolved markers:")
        for name in unresolved:
            print(f"- {name}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
