#!/usr/bin/env python3
"""Heuristic scan for suspicious production placeholders.
Never treat findings as proof; findings require review."""
from pathlib import Path
import argparse, re

PATTERNS = [
    r"\bmockData\b", r"\bfake[A-Z_]", r"\bdummy\b", r"\bplaceholder\b",
    r"temporaryFix", r"TODO", r"FIXME", r"assertTrue\(true\)",
]
EXTS = {".js", ".jsx", ".ts", ".tsx", ".java", ".kt", ".py", ".go", ".rs", ".vue", ".svelte"}
SKIP = {"node_modules", ".git", "dist", "build", "coverage", ".ai", ".ai-runtime", "test", "tests", "__tests__"}

ap = argparse.ArgumentParser()
ap.add_argument("--root", default=".")
args = ap.parse_args()
root = Path(args.root)
for p in root.rglob("*"):
    if not p.is_file() or p.suffix.lower() not in EXTS or any(part in SKIP for part in p.parts):
        continue
    text = p.read_text(encoding="utf-8", errors="ignore")
    for i, line in enumerate(text.splitlines(), 1):
        for pat in PATTERNS:
            if re.search(pat, line, re.I):
                print(f"{p}:{i}: {line.strip()[:180]}")
                break
