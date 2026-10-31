"""Deterministic repository/production-JAR credential gate (never prints values).

This complements, rather than replaces, a full SCA/secret scan.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SECRET_KEY = re.compile(r'^\s*(?:password|secret|ukey|token|authorization|key|api-v3-key|current-secret|previous-secret|config-master-key)\s*:\s*(.+)$', re.I)

def config_issues(text, name):
    for number, line in enumerate(text.splitlines(), 1):
        match = SECRET_KEY.match(line)
        if match:
            value = match.group(1).split(' #', 1)[0].strip().strip('\"\'')
            if value and not value.startswith('${'):
                yield f'{name}:{number}: literal credential; use runtime configuration'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--jar', type=Path)
    args = parser.parse_args()
    issues = []
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    for name in filter(None, tracked):
        path = ROOT / name
        if not path.is_file():
            continue
        if path.suffix.lower() in ('.pfx', '.p12') or (path.suffix == '.pem' and b'PRIVATE KEY' in path.read_bytes()):
            issues.append(f'{name}: tracked private-key material')
        if name == 'src/main/resources/application.yml':
            issues.extend(config_issues(path.read_text(encoding='utf-8-sig'), name))
    if args.jar:
        with zipfile.ZipFile(args.jar) as jar:
            for name in jar.namelist():
                if name.startswith('BOOT-INF/classes/'):
                    if name.endswith(('.pem', '.pfx', '.p12', '.zip', 'application-debug.yml', 'application-zsq-example.yml')):
                        issues.append(f'{name}: forbidden production resource')
                    if name.endswith('/application.yml'):
                        issues.extend(config_issues(jar.read(name).decode('utf-8-sig'), name))
    for issue in issues:
        print(issue)
    print('Release credential gate:', 'FAIL' if issues else 'PASS')
    return bool(issues)

if __name__ == '__main__':
    sys.exit(main())
