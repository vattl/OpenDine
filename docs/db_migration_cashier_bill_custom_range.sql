-- WI-008：收银账单自定义时间范围权限
-- 部署顺序：先执行本迁移，再部署支持 startTime/endTime 的应用 JAR。
-- 幂等：可重复执行。

INSERT IGNORE INTO t_permission
    (permission_code, permission_name, module, remark, sort_order)
VALUES
    ('admin:super', '超级管理员专属能力', 'admin',
     '收银账单自定义历史时间范围等高权限读取能力', 7);

DELETE rp
FROM t_role_permission rp
JOIN t_role r ON r.id = rp.role_id
JOIN t_permission p ON p.id = rp.permission_id
WHERE p.permission_code = 'admin:super'
  AND r.role_code <> 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM t_role r
JOIN t_permission p ON p.permission_code = 'admin:super'
WHERE r.role_code = 'super_admin';

-- 验证：admin:super 只能授予 super_admin；结果应仅包含 super_admin。
SELECT r.role_code, p.permission_code
FROM t_role_permission rp
JOIN t_role r ON r.id = rp.role_id
JOIN t_permission p ON p.id = rp.permission_id
WHERE p.permission_code = 'admin:super';
