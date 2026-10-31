#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path('.')
required=[
 '.ai/rules/CONTRACT_COLLABORATION_RULES.md',
 '.ai/templates/FRONTEND_CONSUMER_HANDOFF.md',
 '.ai/templates/BACKEND_CAPABILITY_REQUEST.md',
 '.ai/templates/CONTRACT_HANDOFF.md']
missing=[x for x in required if not (root/x).exists()]
if missing:
 print('FAIL:', *missing, sep='\n- '); sys.exit(2)
print('PASS: bidirectional contract handoff structure present.')
