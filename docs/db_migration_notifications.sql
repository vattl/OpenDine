-- ============================================================
-- 通知模块（协调文档 §2：通知规则 / 通知试发 / 通知记录）
-- 幂等：可重复执行。已有数据零影响。
-- ============================================================

-- 1) 通知规则
CREATE TABLE IF NOT EXISTS `t_notification_rule` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `name` varchar(128) NOT NULL COMMENT '规则名称',
  `event_type` varchar(64) NOT NULL COMMENT '事件类型：order_new/order_refund/stock_low/shift_close…',
  `channels_json` text COMMENT '通知渠道 JSON 数组，如 ["app","sms","printer"]',
  `recipients_json` text COMMENT '接收人 JSON 数组：[{"name":..,"phone":..,"role":..}]',
  `time_window_json` text COMMENT '生效时段 JSON：{"start":"08:00","end":"22:00","days":[1,2,3]}',
  `frequency_control_json` text COMMENT '频控 JSON：{"minIntervalMinutes":5,"dailyCap":50}',
  `enabled` tinyint NOT NULL DEFAULT 1 COMMENT '1 启用 0 停用',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shop_event` (`shop_id`,`event_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='通知规则';

-- 2) 通知发送记录（仅在线保存近 30 天数据可查；更早数据走归档检索）
CREATE TABLE IF NOT EXISTS `t_notification_delivery` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `rule_id` bigint DEFAULT NULL COMMENT 't_notification_rule.id',
  `event_type` varchar(64) NOT NULL,
  `channel` varchar(16) NOT NULL COMMENT 'app/sms/printer…',
  `recipient_masked` varchar(64) DEFAULT NULL COMMENT '接收人（脱敏存储）',
  `title` varchar(255) DEFAULT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/SENT/FAILED',
  `error` varchar(500) DEFAULT NULL,
  `retry_count` int NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shop_time` (`shop_id`,`created_at`),
  KEY `idx_shop_rule` (`shop_id`,`rule_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='通知发送记录';

-- 3) 权限码注册
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('notifications:view',   '通知规则查看', 'notifications', '通知规则与发送记录查看', 70),
('notifications:manage', '通知规则管理', 'notifications', '通知规则增删改与试发', 71);

-- 4) 接口-权限映射
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',    '/admin/notifications/rules',           'notifications:view|notifications:manage'),
('POST',   '/admin/notifications/rules',           'notifications:manage'),
('PUT',    '/admin/notifications/rules/*',         'notifications:manage'),
('DELETE', '/admin/notifications/rules/*',         'notifications:manage'),
('POST',   '/admin/notifications/rules/*/test',    'notifications:manage'),
('GET',    '/admin/notifications/deliveries',      'notifications:view|notifications:manage');

-- 5) 授权
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('notifications:view','notifications:manage')
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code = 'notifications:view'
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
