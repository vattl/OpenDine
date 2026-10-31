#!/usr/bin/env python3
from pathlib import Path
import argparse, sys

REQUIRED_SECTIONS = {
    'WORK_ITEM.md': ['## Requirement Contract', '## Acceptance Decision'],
    'IMPACT_MAP.md': ['## Authoritative Owner', '## Layer Coverage'],
    'IMPLEMENTATION_DESIGN.md': ['## Root Fix / Owner', '## Verification Strategy'],
}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('path', help='Work Item directory')
    ap.add_argument('--strict', action='store_true')
    args=ap.parse_args()
    root=Path(args.path)
    problems=[]
    for name, sections in REQUIRED_SECTIONS.items():
        p=root/name
        if not p.exists():
            if args.strict: problems.append(f'missing {name}')
            continue
        txt=p.read_text(encoding='utf-8', errors='replace')
        for sec in sections:
            if sec not in txt: problems.append(f'{name}: missing section {sec}')
    impact=root/'IMPACT_MAP.md'
    if impact.exists():
        txt=impact.read_text(encoding='utf-8', errors='replace')
        if args.strict and '| UNKNOWN |' in txt:
            problems.append('IMPACT_MAP.md contains UNKNOWN classifications')
    if problems:
        print('WORK ITEM VALIDATION: FAIL')
        for x in problems: print('-',x)
        return 1
    print('WORK ITEM VALIDATION: PASS')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
