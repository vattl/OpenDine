# -*- coding: utf-8 -*-
"""权限审计 v2：聚合 docs 下所有 sql 中的 t_api_permission 映射 + 代码内置映射，对比全仓端点"""
import io
import os
import re

ROOT = r'G:\Mini Program\my_project_server\server\src\main\java\com\lanf\controller'
DOCS = r'G:\Mini Program\my_project_server\server\docs'
BUILTIN = r'G:\Mini Program\my_project_server\server\src\main\java\com\lanf\config\ApiPermissionMapping.java'

# ---------- 1. 代码内置 ----------
builtin = set()
with io.open(BUILTIN, 'r', encoding='utf-8') as f:
    for line in f:
        m = re.search(r'add\(\s*(METHOD_\w+)\s*,\s*"([^"]+)"\s*,', line)
        if m:
            builtin.add((m.group(1).replace('METHOD_', ''), m.group(2).rstrip('/') or '/'))

# ---------- 2. 聚合 docs 全部 sql 的 t_api_permission INSERT ----------
sql_files = []
for fn in os.listdir(DOCS):
    if fn.endswith('.sql'):
        sql_files.append(os.path.join(DOCS, fn))

dbmap = set()
TUPLE_RE = re.compile(r"\(\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*\)")
for sp in sql_files:
    with io.open(sp, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    for m in re.finditer(r'INSERT.{0,400}?t_api_permission.{0,200}?VALUES\s*(.*?);', content, re.S | re.I):
        block = m.group(1)
        for t in TUPLE_RE.finditer(block):
            method, path, code = t.group(1), t.group(2), t.group(3)
            # 保留 path 原样：DB 以「结尾 /」表示前缀通配，如 '/admin/administrator/'
            if method in ('GET', 'POST', 'PUT', 'DELETE', '*'):
                dbmap.add((method, path, code))

print('内置映射:', len(builtin), '| DB 聚合映射:', len(dbmap), '| SQL 文件:', len(sql_files))

# ---------- 3. 扫描端点（类级前缀只取 class 声明前最近的 @RequestMapping） ----------
CLS_RE = re.compile(r'@RequestMapping\(\s*(?:value\s*=\s*)?"([^"]*)"')
MAPPING_RE = re.compile(r'@(Get|Post|Put|Delete|Request)Mapping\(\s*(?:value\s*=\s*)?"([^"]*)"')
endpoints = []

def norm(p):
    p = re.sub(r'\{[^}]*\}', '{id}', p)
    return p.rstrip('/') or '/'

for dirpath, _, files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith('.java'):
            continue
        fp = os.path.join(dirpath, fn)
        with io.open(fp, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        cls_prefix = ''
        class_line = -1
        for i, line in enumerate(lines):
            if re.search(r'\bclass\s+\w+', line):
                class_line = i
                break
        # class 声明前最近的类级 @RequestMapping（仅匹配 @RestController 下的类注解行）
        for i in range(class_line - 1, max(-1, class_line - 8), -1):
            if '@RequestMapping' in lines[i] and 'Mapping(' in lines[i]:
                cm = CLS_RE.search(lines[i])
                if cm:
                    cls_prefix = norm(cm.group(1))
                break
        for i, line in enumerate(lines):
            if i <= class_line:
                continue
            mm = MAPPING_RE.search(line)
            if mm and 'Mapping(' in line:
                m_path = norm(mm.group(2))
                full = norm(cls_prefix + m_path) if m_path.startswith('/') else norm(cls_prefix + '/' + m_path)
                method_name = ''
                for j in range(i + 1, min(i + 5, len(lines))):
                    mm2 = re.search(r'public\s+\S+\s+(\w+)\s*\(', lines[j])
                    if mm2:
                        method_name = mm2.group(1)
                        break
                endpoints.append((mm.group(1), full, fn.replace('.java', ''), method_name, i + 1))

# ---------- 4. 匹配（path 保留原样：尾 / = 前缀通配，* = 段通配，如 /admin/access/roles/*） ----------
def matched(method, path):
    allmap = [(m, p) for (m, p) in builtin] + [(m, p) for (m, p, _) in dbmap]
    cands = [(m, p) for (m, p) in allmap if m == method or m == '*']
    for m, p in sorted(cands, key=lambda x: -len(x[1])):
        if p.endswith('/'):
            if path.startswith(p):
                return True
            continue
        if '*' in p:
            head, _, tail = p.partition('*')
            if path.startswith(head) and path.endswith(tail) and len(path) >= len(head) + len(tail):
                return True
            continue
        if path == p.rstrip('/') or '/':
            return True
    return False

missing = []
for method, path, cls, mname, ln in endpoints:
    if not (path.startswith('/admin/') or path.startswith('/cashier')
            or path.startswith('/api/admin/cashier') or path.startswith('/pay/offline-collect')):
        continue
    if path in ('/admin/me/permissions', '/admin/me/shops', '/admin/app/version',
                '/admin/push/device/register', '/admin/push/device/unregister', '/admin/push/preference'):
        continue
    if not matched(method.upper(), path):
        missing.append((method, path, cls, mname, ln))

print('扫描端点(admin/cashier/pay):', len(endpoints), '| 无映射缺口:', len(missing))
for method, path, cls, mname, ln in sorted(missing, key=lambda x: (x[2], x[1])):
    print('%-6s %-52s %s.%s L%s' % (method, path, cls, mname, ln))
