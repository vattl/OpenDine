#!/usr/bin/env python3
"""Heuristic production-integrity scanner.

This script is intentionally advisory. It flags suspicious terms in likely production
paths; it does not decide correctness. Use alongside engineering review.
"""
from pathlib import Path
import argparse, re, sys

DEFAULT_PATTERNS = [
    r"\bmock(data)?\b", r"\bfake\b", r"\bdummy\b", r"\bplaceholder\b",
    r"\btemporary(Fix)?\b", r"\bTODO\b", r"\bFIXME\b",
]
EXCLUDED = {"node_modules", ".git", "dist", "build", "target", ".next", "coverage", ".ai", "docs", "design", "tests", "test", "__tests__"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    rx = re.compile("|".join(f"(?:{p})" for p in DEFAULT_PATTERNS), re.I)
    hits = []
    for p in root.rglob("*"):
        if not p.is_file() or any(part in EXCLUDED for part in p.parts):
            continue
        if p.suffix.lower() not in {".js", ".jsx", ".ts", ".tsx", ".java", ".kt", ".py", ".go", ".rs", ".cs", ".php", ".vue", ".svelte"}:
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if rx.search(line):
                hits.append((p.relative_to(root), i, line.strip()[:220]))
    if hits:
        print("Suspicious production-path patterns (review required):")
        for p, n, line in hits[:200]:
            print(f"{p}:{n}: {line}")
        if len(hits) > 200:
            print(f"... {len(hits)-200} more")
        return 2 if args.strict else 0
    print("No suspicious production-path patterns found by heuristic scan.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
