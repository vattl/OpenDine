# -*- coding: utf-8 -*-
"""
Replay StrReplace patches on server/docs/openapi.yaml from agent transcripts.
Restores uncommitted openapi evolution (e.g. v1.2.85) after accidental git checkout.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPENAPI = ROOT / "docs" / "openapi.yaml"
TRANSCRIPTS = [
    Path(r"C:\Users\Admin\.cursor\projects\g-Mini-Program-my-project-server\agent-transcripts\492b6fdc-1866-48c1-8df5-499cd8d581b0\492b6fdc-1866-48c1-8df5-499cd8d581b0.jsonl"),
    Path(r"C:\Users\Admin\.cursor\projects\g-Mini-Program-my-project-server\agent-transcripts\b3ec86bb-96bd-4562-bfec-911b0f77c10f\b3ec86bb-96bd-4562-bfec-911b0f77c10f.jsonl"),
]


def git_restore():
    repo = ROOT.parent
    subprocess.run(
        ["git", "checkout", "--", "server/docs/openapi.yaml"],
        cwd=repo,
        check=True,
    )


def collect_patches() -> list[dict]:
    patches = []
    for fp in TRANSCRIPTS:
        if not fp.exists():
            print("warn: missing transcript", fp, file=sys.stderr)
            continue
        for i, line in enumerate(fp.read_text(encoding="utf-8").splitlines()):
            if "openapi.yaml" not in line or '"StrReplace"' not in line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            for part in obj.get("message", {}).get("content", []):
                if part.get("name") != "StrReplace":
                    continue
                inp = part.get("input") or {}
                path = inp.get("path", "").replace("\\", "/")
                if not path.endswith("server/docs/openapi.yaml") and not path.endswith("openapi.yaml"):
                    continue
                old = inp.get("old_string")
                new = inp.get("new_string")
                if old is None or new is None or old == new:
                    continue
                patches.append(
                    {
                        "file": str(fp.name),
                        "line": i + 1,
                        "old": old,
                        "new": new,
                        "replace_all": bool(inp.get("replace_all")),
                    }
                )
    return patches


def apply_patches(patches: list[dict]) -> tuple[int, int]:
    text = OPENAPI.read_text(encoding="utf-8")
    ok = 0
    fail = 0
    for p in patches:
        old, new = p["old"], p["new"]
        if p["replace_all"]:
            if old not in text:
                fail += 1
                print(f"FAIL [{p['file']}:{p['line']}] replace_all old not found ({len(old)} chars)")
                continue
            text = text.replace(old, new)
            ok += 1
            continue
        if old not in text:
            fail += 1
            print(f"FAIL [{p['file']}:{p['line']}] old not found ({len(old)} chars)")
            continue
        text = text.replace(old, new, 1)
        ok += 1
    OPENAPI.write_text(text, encoding="utf-8", newline="\n")
    return ok, fail


def main():
    print("Restoring base from git...")
    git_restore()
    base_ver = re.search(r"^\s*version:\s*([\d.]+)\s*$", OPENAPI.read_text(encoding="utf-8"), re.M)
    print("Base version:", base_ver.group(1) if base_ver else "?")

    patches = collect_patches()
    print("Collected patches:", len(patches))

    ok, fail = apply_patches(patches)
    text = OPENAPI.read_text(encoding="utf-8")
    ver = re.search(r"^\s*version:\s*([\d.]+)\s*$", text, re.M)
    kds_paths = len(re.findall(r"^\s+/kds/", text, re.M))
    print(f"Applied OK: {ok}, failed: {fail}")
    print("Result version:", ver.group(1) if ver else "?")
    print("KDS paths:", kds_paths)
    print("Lines:", text.count("\n") + 1)
    print("Bytes:", len(text.encode("utf-8")))


if __name__ == "__main__":
    main()
