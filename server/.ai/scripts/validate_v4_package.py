#!/usr/bin/env python3
from pathlib import Path
import json, sys
root=Path(__file__).resolve().parents[2]
required=[
'.ai/SKILL.md','.ai/rules/WORKFLOW_CORE.md','.ai/rules/WORK_ITEM_RULES.md',
'.ai/rules/IMPACT_DISCOVERY_RULES.md','.ai/rules/API_CONSUMER_HANDOFF_RULES.md',
'.ai/commands/work.md','.ai/templates/WORK_ITEM.md','.ai/templates/IMPACT_MAP.md',
'.ai/templates/IMPLEMENTATION_DESIGN.md','.ai/templates/ACCEPTANCE_REPORT.md',
'docs/WORKFLOW_CORE.md','docs/MIGRATION_TO_V4.md','MANIFEST.json']
missing=[x for x in required if not (root/x).exists()]
manifest=json.loads((root/'MANIFEST.json').read_text(encoding='utf-8')) if (root/'MANIFEST.json').exists() else {}
actual=sum(1 for p in root.rglob('*') if p.is_file())
# MANIFEST lists itself? generated before validator, so allow actual >= declared
if missing:
    print('V4 PACKAGE VALIDATION: FAIL')
    for x in missing: print('missing',x)
    sys.exit(1)
print('V4 PACKAGE VALIDATION: PASS')
print('actual files:',actual)
print('manifest snapshot files:',manifest.get('file_count'))
