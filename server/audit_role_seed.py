# -*- coding: utf-8 -*-
"""聚合 v2：t_permission 码清单 + role_code→permission_code 授权矩阵"""
import io, re, os

DOCS = r'G:\Mini Program\my_project_server\server\docs'
ROLE_GRANT = re.compile(r"role_code\s+IN\s*\(([^)]*)\)(.*?)(?:permission_code|p\.permission_code)\s+IN\s*\(([^)]*)\)", re.S)
ROLE_EQ = re.compile(r"role_code\s*=\s*'([^']+)'")
PERM5 = re.compile(r"\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*(-?\d+)\s*\)")

perms = {}      # code -> (name, module)
grants = {}     # role_code -> set(permission_code)

for fn in os.listdir(DOCS):
    if not fn.endswith('.sql'):
        continue
    with io.open(os.path.join(DOCS, fn), 'r', encoding='utf-8', errors='ignore') as f:
        c = f.read()
    for m in re.finditer(r'INSERT[^;]{0,600}?`?t_permission`?[^;]*?VALUES\s*(.*?);', c, re.S | re.I):
        for row in PERM5.finditer(m.group(1)):
            code, name, module = row.group(1), row.group(2), row.group(3)
            perms[code] = (name, module)
    # 授权：SELECT ... WHERE r.role_code IN (...) AND p.permission_code IN (...)
    for m in ROLE_GRANT.finditer(c):
        roles_s = [x.strip().strip("'") for x in m.group(1).split(',')]
        perms_s = [x.strip().strip("'") for x in m.group(3).split(',')]
        for r in roles_s:
            grants.setdefault(r, set()).update(perms_s)
    # 授权：role_code = 'x' AND permission_code IN (...)
    for m in re.finditer(r"WHERE\s+r\.role_code\s*=\s*'([^']+)'.{0,200}?permission_code\s+IN\s*\(([^)]*)\)", c, re.S):
        perms_s = [x.strip().strip("'") for x in m.group(2).split(',')]
        grants.setdefault(m.group(1), set()).update(perms_s)

print('== t_permission 权限码全集（{}）=='.format(len(perms)))
for code in sorted(perms):
    print('  {:<32} {} / {}'.format(code, perms[code][0], perms[code][1]))

print('== 角色授权矩阵（{} 角色）=='.format(len(grants)))
all_codes = sorted(set(perms) | set(x for v in grants.values() for x in v))
print('  {:<14} {}'.format('role', ' '.join('{:>22}'.format(c) for c in all_codes)))
for r in sorted(grants):
    row = ' '.join('{:>22}'.format('Y' if c in grants[r] else '-') for c in all_codes)
    print('  {:<14} {}'.format(r, row))
