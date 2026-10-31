#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
required = [
    'VERSION.md',
    '.ai/commands/work.md',
    '.ai/rules/WORKFLOW_CORE.md',
    '.ai/rules/BUSINESS_INVARIANT_RULES.md',
    '.ai/rules/SCENARIO_MATRIX_RULES.md',
    '.ai/rules/IMPLEMENTATION_READY_RULES.md',
    '.ai/rules/IMPACT_MAP_AUTHORITY_RULES.md',
    '.ai/rules/COMPLETION_STATE_RULES.md',
    '.ai/templates/BUSINESS_INVARIANTS.md',
    '.ai/templates/SCENARIO_MATRIX.md',
    '.ai/templates/IMPLEMENTATION_READY_REPORT.md',
    'docs/project/BUSINESS_RULES.md',
    'docs/WORKFLOW_V4_2.md',
    '.ai/project/business-rules.json',
]
missing=[p for p in required if not (root/p).exists()]
version=(root/'VERSION.md').read_text(encoding='utf-8') if (root/'VERSION.md').exists() else ''
errors=[]
if missing: errors.append('missing: '+', '.join(missing))
if 'v4.2' not in version: errors.append('VERSION.md does not identify v4.2')
if errors:
    print('FAIL')
    for e in errors: print('-',e)
    sys.exit(1)
print('PASS: v4.2 package structure valid')
