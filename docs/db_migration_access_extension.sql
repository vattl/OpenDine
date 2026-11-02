-- ============================================================
-- 员工与门店授权 / 角色管理 / 权限解释（协调文档 §2 权限三行）
-- 幂等：可重复执行。已有数据零影响。
-- ============================================================

-- 1) t_role 增加乐观锁版本列（守护式加列）
DROP PROCEDURE IF EXISTS `p_role_add_version_col`;
DELIMITER $$
CREATE PROCEDURE `p_role_add_version_col`()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_role' AND COLUMN_NAME = 'version') THEN
    ALTER TABLE `t_role` ADD COLUMN `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本';
  END IF;
END$$
DELIMITER ;
CALL `p_role_add_version_col`();
DROP PROCEDURE IF EXISTS `p_role_add_version_col`;

-- 2) 权限码注册
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('access:view',   '员工与权限查看', 'access', '员工授权/角色/权限解释查看', 90),
('access:manage', '员工与权限管理', 'access', '员工角色分配、角色增删改', 91);

-- 3) 接口-权限映射
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',    '/admin/access/employees',        'access:view|access:manage'),
('POST',   '/admin/access/employees',        'access:manage'),
('PUT',    '/admin/access/employees/*',      'access:manage'),
('GET',    '/admin/access/roles',            'access:view|access:manage'),
('POST',   '/admin/access/roles',            'access:manage'),
('PUT',    '/admin/access/roles/*',          'access:manage'),
('DELETE', '/admin/access/roles/*',          'access:manage'),
('POST',   '/admin/access/evaluate',         'access:view|access:manage');

-- 4) 授权
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('access:view','access:manage')
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code = 'access:view'
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
