#!/usr/bin/env python3
"""v4.3 HTML prototype and explicit user-approval gate for UI work.

This validator checks evidence presence. It does not judge design quality.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys

HTML_EXTS = {'.html', '.htm'}
IMAGE_EXTS = {'.png', '.jpg', '.jpeg', '.webp'}


def contains_approval(path: Path) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding='utf-8', errors='ignore')
    return re.search(
        r'^\s*Approval Status\s*:\s*APPROVED\s*$', text, re.IGNORECASE | re.MULTILINE
    ) is not None


def contains_presentation(path: Path) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding='utf-8', errors='ignore')
    return re.search(
        r'^\s*Presented To User\s*:\s*YES\s*$', text, re.IGNORECASE | re.MULTILINE
    ) is not None


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('--root', default='.')
    p.add_argument('--work-item', default='')
    p.add_argument('--require-ui-prototype', action='store_true')
    p.add_argument('--require-structural-ui', action='store_true')
    p.add_argument('--prototype-dir', default='')
    args = p.parse_args()

    root = Path(args.root).resolve()
    base_required = [
        root/'docs/project/DESIGN_SYSTEM_PROFILE.md',
        root/'.ai/rules/UI_DESIGN_TRACK_RULES.md',
        root/'.ai/rules/WORKFLOW_ROUTER_RULES.md',
        root/'.ai/rules/PROTOTYPE_ENFORCEMENT_RULES.md',
    ]
    missing = [str(x.relative_to(root)) for x in base_required if not x.exists()]
    if missing:
        print('UI GATE: FAIL')
        print('Missing prerequisites:')
        for m in missing: print('-', m)
        return 2

    if not (args.require_ui_prototype or args.require_structural_ui):
        print('UI GATE: PASS (HTML prototype enforcement not requested)')
        return 0

    if args.prototype_dir:
        candidates = [root/args.prototype_dir]
    else:
        dirs = []
        design = root/'design'
        if design.exists():
            dirs.extend([p for p in design.rglob('*') if p.is_dir() and ('prototype' in p.name.lower() or 'UI' in p.name)])
        candidates = dirs or [design]

    html_prototypes=[]; images=[]; approvals=[]; presentations=[]; approved_presentations=[]; locks=[]; coverage=[]
    for d in candidates:
        if not d.exists(): continue
        for f in d.rglob('*'):
            if not f.is_file(): continue
            low=f.name.lower()
            if f.suffix.lower() in HTML_EXTS and 'prototype' in str(f).lower(): html_prototypes.append(f)
            if f.suffix.lower() in IMAGE_EXTS: images.append(f)
            if 'approval' in low and f.suffix.lower()=='.md':
                approved = contains_approval(f)
                presented = contains_presentation(f)
                if approved: approvals.append(f)
                if presented: presentations.append(f)
                if approved and presented: approved_presentations.append(f)
            if ('ui_lock' in low or 'ui-lock' in low or 'lock_manifest' in low) and f.suffix.lower() in {'.md','.json'}: locks.append(f)
            if 'prototype_coverage' in low and f.suffix.lower()=='.md': coverage.append(f)

    blockers=[]
    if not html_prototypes: blockers.append('HTML prototype artifact (.html/.htm) missing')
    if not images: blockers.append('prototype visual reference/screenshot missing')
    if not presentations: blockers.append('prototype has not been presented to user (Presented To User: YES required)')
    if not approvals: blockers.append('explicit user approval evidence missing (Approval Status: APPROVED required)')
    if presentations and approvals and not approved_presentations:
        blockers.append('presentation and explicit approval must be recorded in the same approval record')
    if not locks: blockers.append('UI lock evidence missing')

    if blockers:
        print('UI GATE: BLOCKED')
        print('Prototype Requirement: REQUIRED')
        print('Prototype Mode: HTML')
        for b in blockers: print('-', b)
        print('Production Editing: FORBIDDEN')
        return 3

    print('UI GATE: PASS')
    print(f'HTML prototypes: {len(html_prototypes)}')
    print(f'Visual references: {len(images)}')
    print(f'User presentation records: {len(approved_presentations)}')
    print(f'Explicit approvals: {len(approved_presentations)}')
    print(f'UI lock records: {len(locks)}')
    if coverage:
        print(f'Coverage matrices: {len(coverage)}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
