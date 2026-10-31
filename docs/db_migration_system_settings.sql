-- ============================================================
-- 系统设置模块（协调文档 §2：设置导航概览 / 门店设置详情 / 保存门店设置 / 恢复总部继承）
-- 幂等：可重复执行。已有数据零影响。
-- ============================================================

-- 1) 总部级设置默认值（module 为主键）
CREATE TABLE IF NOT EXISTS `t_hq_settings` (
  `module` varchar(64) NOT NULL COMMENT '模块标识：store/printing/payment/notifications…',
  `payload_json` longtext COMMENT '模块配置 JSON',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `updated_by` int DEFAULT NULL COMMENT '最后更新管理员 t_admin.id',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`module`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='总部设置默认值';

-- 2) 门店设置覆盖（行存在 = source 为 SHOP；不存在 = 继承总部/系统）
CREATE TABLE IF NOT EXISTS `t_shop_settings` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `module` varchar(64) NOT NULL COMMENT '模块标识',
  `payload_json` longtext COMMENT '覆盖配置 JSON（仅存被覆盖字段）',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `updated_by` int DEFAULT NULL COMMENT '最后更新管理员',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop_module` (`shop_id`,`module`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店设置覆盖';

-- 3) 权限码注册
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('settings:view',   '设置导航查看', 'settings', '系统设置导航概览、门店设置详情查看', 60),
('settings:manage', '门店设置管理', 'settings', '保存门店设置覆盖、恢复总部继承', 61);

-- 4) 接口-权限映射（DbApiPermissionMapping 启动/重载后生效）
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',    '/admin/settings/overview',       'settings:view|settings:manage'),
('GET',    '/admin/settings/store',          'settings:view|settings:manage'),
('PUT',    '/admin/settings/store',          'settings:manage'),
('DELETE', '/admin/settings/store/override', 'settings:manage');

-- 5) 授权：超级管理员全量；门店管理员授予查看+管理（按现有角色码）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('settings:view','settings:manage')
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('settings:view','settings:manage')
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
