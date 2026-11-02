-- ============================================================
-- 修复：t_api_permission 使用的权限码在 t_permission 字典中缺失
-- 审计发现：
--   1) 最新全量接口映射 db_migration_api_permission_full.sql 使用 'public'
--      用于 GET /admin/me/permissions、GET /admin/me/shops、POST /adminLogin，
--      但 t_permission 字典中不存在 'public' → SysInterceptor 精确匹配
--      hasRequiredPermission(permissions, "public") 必然 403。
--   2) 旧版 init_api_permission.sql 曾使用 5 个字典外权限码
--      (daily:settle / shop:manage / user:points / payment:config:read / payment:config:write)。
--      若线上库尚未执行 db_migration_api_permission_full.sql，这 5 个码仍在接口映射中使用，
--      同样匹配不到权限。此处一并补入字典兜底。
-- 幂等：均使用 INSERT IGNORE（依赖 uk_permission_code 唯一键）。
-- ============================================================

-- 1. 补齐缺失权限码到 t_permission
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('public',                 '公开接口',     '系统', '登录即可访问的接口（我的权限/我的门店/登录）', 130),
('daily:settle',           '日结',         '订单', '日结操作与查询（兼容旧接口映射）', 33),
('shop:manage',            '门店管理',     '订单', '门店信息管理（兼容旧接口映射）', 34),
('user:points',            '积分操作',     '会员', '手动加减积分（兼容旧接口映射）', 83),
('payment:config:read',    '支付配置查看', '支付', '支付配置只读（兼容旧接口映射）', 121),
('payment:config:write',   '支付配置编辑', '支付', '支付配置写入（兼容旧接口映射）', 122);

-- 2. 给【所有角色】授予 public（角色-权限授权是插入时快照，必须显式补授，
--    否则老板等既有角色仍拿不到 public，/admin/me/permissions 依然 403）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE p.permission_code = 'public';

-- 3. 校验（应输出 6 行、无重复）
-- SELECT permission_code, permission_name FROM t_permission WHERE permission_code IN
--   ('public','daily:settle','shop:manage','user:points','payment:config:read','payment:config:write');
-- SELECT r.role_code, COUNT(*) AS grant_cnt FROM t_role_permission rp
--   JOIN t_role r ON rp.role_id = r.id
--   JOIN t_permission p ON rp.permission_id = p.id
-- WHERE p.permission_code = 'public' GROUP BY r.role_code;
