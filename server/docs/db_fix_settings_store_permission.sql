-- ============================================================
-- 修复：GET /admin/settings/store 返回 403「接口权限未配置」
-- 根因：t_api_permission 唯一键 uk_path_pattern 仅锁 path_pattern（一 path 一条，不区分 method）；
--       db_migration_api_permission_full.sql 的 PUT /admin/settings/store（ON DUPLICATE KEY UPDATE）
--       把 db_migration_system_settings.sql 登记的 GET 记录覆盖成了 PUT，导致 GET 无映射。
-- 修复内容（幂等，可重复执行）：
--   1) /admin/settings/store 收敛为 method='*'，权限码 settings:view|settings:manage（GET 读任一命中，PUT 写需 manage）
--   2) /admin/settings/overview 权限码恢复为 settings:view|settings:manage（与权威登记一致，此前被覆盖为 order:config:shop）
--   3) cashier 角色补 settings:view（收银端需读取门店设置；缺此码时 GET 会 403「无权限」）
-- 注意：执行后需重载权限映射（调用 POST /admin/rbac/api-permissions/reload 或重启服务）方可即时生效。
-- ============================================================

-- 1) /admin/settings/store → method='*'（GET 读 / PUT 写共用一条映射）
UPDATE t_api_permission
SET method = '*',
    permission_code = 'settings:view|settings:manage',
    remark = '设置-门店设置（GET读/PUT写共用）'
WHERE path_pattern = '/admin/settings/store';

-- 2) /admin/settings/overview → 恢复 settings:view|settings:manage
UPDATE t_api_permission
SET permission_code = 'settings:view|settings:manage',
    remark = '设置-概览'
WHERE path_pattern = '/admin/settings/overview';

-- 3) cashier 角色补 settings:view（幂等：已存在则跳过）
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM t_role r, t_permission p
WHERE r.role_code = 'cashier'
  AND p.permission_code = 'settings:view'
  AND NOT EXISTS (
      SELECT 1 FROM t_role_permission trp
      WHERE trp.role_id = r.id AND trp.permission_id = p.id
  );

-- ============================================================
-- 校验（执行后应各返回 1 行）：
--   SELECT method, path_pattern, permission_code, remark FROM t_api_permission
--   WHERE path_pattern IN ('/admin/settings/store','/admin/settings/overview');
--   SELECT COUNT(*) FROM t_role_permission trp
--   JOIN t_role r ON r.id=trp.role_id JOIN t_permission p ON p.id=trp.permission_id
--   WHERE r.role_code='cashier' AND p.permission_code='settings:view';  -- 应 >=1
-- ============================================================
