#!/usr/bin/env python3
from pathlib import Path
import json, sys
root=Path('.')
files=[
 '.ai/project/project-profile.json',
 '.ai/project/architecture-map.json',
 '.ai/project/design-system.json',
 '.ai/project/baseline-meta.json',
 'docs/project/PROJECT_PROFILE.md',
 'docs/project/ARCHITECTURE_MAP.md',
 'docs/project/DESIGN_SYSTEM_PROFILE.md',
 'docs/project/BASELINE_HISTORY.md']
missing=[f for f in files if not (root/f).exists()]
if missing:
 print('FAIL missing baseline files:', *missing, sep='\n- '); sys.exit(2)
for f in files[:4]:
 try: json.loads((root/f).read_text(encoding='utf-8'))
 except Exception as e:
  print(f'FAIL invalid JSON {f}: {e}'); sys.exit(3)
print('PASS: baseline structure valid.')
