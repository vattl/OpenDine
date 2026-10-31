#!/usr/bin/env python3
"""Validate the machine-readable business invariant source and its Markdown view."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys


REQUIRED_FIELDS = ("id", "status", "capability", "owner", "rule", "verification")
ALLOWED_STATUSES = {"ENFORCED", "TARGET"}
ID_PATTERN = re.compile(r"^INV-[A-Z][A-Z0-9_]*-\d{3}$")


def load_rules(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as stream:
        payload = json.load(stream)
    if not isinstance(payload, dict) or not isinstance(payload.get("invariants"), list):
        raise ValueError("business rules JSON must contain an invariants array")
    return payload


def validate_payload(payload: dict) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for index, item in enumerate(payload.get("invariants", []), start=1):
        if not isinstance(item, dict):
            errors.append(f"invariant #{index} must be an object")
            continue
        for name in REQUIRED_FIELDS:
            value = item.get(name)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"invariant #{index} missing non-empty {name}")
        invariant_id = item.get("id", "")
        if invariant_id and not ID_PATTERN.fullmatch(invariant_id):
            errors.append(f"invalid invariant id: {invariant_id}")
        if invariant_id in seen:
            errors.append(f"duplicate invariant id: {invariant_id}")
        seen.add(invariant_id)
        if item.get("status") not in ALLOWED_STATUSES:
            errors.append(
                f"invariant {invariant_id or '#'+str(index)} status must be one of: "
                + ", ".join(sorted(ALLOWED_STATUSES))
            )
    if not seen:
        errors.append("at least one invariant is required")
    return errors


def markdown_ids(text: str) -> set[str]:
    return set(re.findall(r"(?m)^###\s+(INV-[A-Z][A-Z0-9_]*-\d{3})\s*$", text))


def validate_markdown(payload: dict, markdown: str) -> list[str]:
    expected = {item["id"] for item in payload.get("invariants", []) if isinstance(item, dict) and item.get("id")}
    actual = markdown_ids(markdown)
    errors: list[str] = []
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        errors.append("Markdown missing invariant IDs: " + ", ".join(missing))
    if extra:
        errors.append("Markdown contains unknown invariant IDs: " + ", ".join(extra))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rules", default=".ai/project/business-rules.json")
    parser.add_argument("--doc", default="docs/project/BUSINESS_RULES.md")
    args = parser.parse_args()

    try:
        payload = load_rules(Path(args.rules))
        errors = validate_payload(payload)
        doc_path = Path(args.doc)
        if not doc_path.is_file():
            errors.append(f"Markdown view missing: {doc_path}")
        else:
            errors.extend(validate_markdown(payload, doc_path.read_text(encoding="utf-8")))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        errors = [str(exc)]

    if errors:
        print("BUSINESS RULES: FAIL")
        for error in errors:
            print(f"- {error}")
        return 2
    print(f"BUSINESS RULES: PASS ({len(payload['invariants'])} invariants)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
