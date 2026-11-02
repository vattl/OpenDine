#!/usr/bin/env python3
from pathlib import Path
import sys, json
root=Path('.')
required=[
 '.ai/SKILL.md','.ai/commands/work.md','.ai/commands/baseline.md','.ai/commands/baseline-check.md','.ai/commands/rebaseline.md','.ai/commands/contract-handoff.md',
 '.ai/rules/WORKFLOW_ROUTER_RULES.md','.ai/rules/PRE_EDIT_GUARD.md','.ai/rules/PROJECT_BASELINE_RULES.md','.ai/rules/CONTRACT_COLLABORATION_RULES.md','.ai/rules/DATA_FEASIBILITY_RULES.md',
 '.ai/templates/FRONTEND_CONSUMER_HANDOFF.md','.ai/templates/BACKEND_CAPABILITY_REQUEST.md',
 'docs/project/PROJECT_PROFILE.md','docs/project/ARCHITECTURE_MAP.md','docs/project/DESIGN_SYSTEM_PROFILE.md',
 'README.md','VERSION.md','AGENTS.md']
missing=[x for x in required if not (root/x).exists()]
if missing:
 print('FAIL missing required v4.1 files:'); print('\n'.join(missing)); sys.exit(2)
version=(root/'VERSION.md').read_text(encoding='utf-8')
if 'v4.1' not in version:
 print('FAIL VERSION.md is not v4.1'); sys.exit(3)
print(f'PASS: v4.1 required structure present. Files={sum(1 for p in root.rglob("*") if p.is_file())}')
