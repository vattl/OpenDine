-- Mobile admin APP backend support: permissions, push devices, version policy and cashier idempotency.
-- MySQL 8.0+, idempotent where practical.
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `t_admin_push_device` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL,
  `shop_id` int NOT NULL,
  `device_token` varchar(512) NOT NULL,
  `platform` varchar(16) NOT NULL,
  `channel` varchar(16) NOT NULL,
  `app_version` varchar(32) NULL,
  `device_model` varchar(128) NULL,
  `enabled` tinyint NOT NULL DEFAULT 1,
  `last_registered_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_push_device_token` (`device_token`),
  KEY `idx_admin_push_shop_enabled` (`shop_id`,`enabled`),
  KEY `idx_admin_push_admin` (`admin_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运营APP厂商推送设备';

CREATE TABLE IF NOT EXISTS `t_admin_push_preference` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL,
  `shop_id` int NOT NULL,
  `types_json` varchar(2048) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_push_preference` (`admin_id`,`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运营APP通知偏好';

CREATE TABLE IF NOT EXISTS `t_order_client_request` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `admin_id` int NULL,
  `client_request_id` varchar(128) NOT NULL,
  `request_path` varchar(128) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'PROCESSING',
  `response_snapshot` longtext NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_client_request` (`shop_id`,`client_request_id`),
  KEY `idx_order_client_request_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收银APP写请求24小时幂等账本';

CREATE TABLE IF NOT EXISTS `t_admin_app_version` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `platform` varchar(16) NOT NULL,
  `channel` varchar(32) NOT NULL DEFAULT 'mobile',
  `latest` varchar(32) NOT NULL,
  `min_supported` varchar(32) NOT NULL,
  `force_update` tinyint NOT NULL DEFAULT 0,
  `release_notes` text NULL,
  `download_url` varchar(1024) NULL,
  `enabled` tinyint NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_app_version` (`platform`,`channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运营APP版本策略';

INSERT INTO `t_admin_app_version`
(`platform`,`channel`,`latest`,`min_supported`,`force_update`,`release_notes`,`download_url`,`enabled`) VALUES
('android','mobile','2.0.1','2.0.0',0,'移动运营端首版联调策略',NULL,1),
('ios','mobile','2.0.1','2.0.0',0,'移动运营端首版联调策略',NULL,1)
ON DUPLICATE KEY UPDATE `updated_at`=`updated_at`;

INSERT IGNORE INTO `t_permission`
(`permission_code`,`permission_name`,`module`,`remark`,`sort_order`) VALUES
('announcement:view','公告只读','announcement','运营APP公告列表与详情只读权限',49),
('table:operate','桌台操作','table','开台、并台、换台、清台权限',45);

INSERT IGNORE INTO `t_role_permission` (`role_id`,`permission_id`)
SELECT r.id,p.id FROM `t_role` r JOIN `t_permission` p ON p.permission_code='announcement:view'
WHERE r.role_code='super_admin';

INSERT IGNORE INTO `t_role_permission` (`role_id`,`permission_id`)
SELECT DISTINCT rp.role_id,p_new.id
FROM `t_role_permission` rp
JOIN `t_permission` p_old ON p_old.id=rp.permission_id
JOIN `t_permission` p_new ON p_new.permission_code='announcement:view'
WHERE p_old.permission_code IN ('announcement:manage','order:view','cashier:operate','table:manage');

INSERT IGNORE INTO `t_role_permission` (`role_id`,`permission_id`)
SELECT r.id,p.id FROM `t_role` r JOIN `t_permission` p ON p.permission_code='table:operate'
WHERE r.role_code='super_admin';

INSERT IGNORE INTO `t_role_permission` (`role_id`,`permission_id`)
SELECT DISTINCT rp.role_id,p_new.id
FROM `t_role_permission` rp
JOIN `t_permission` p_old ON p_old.id=rp.permission_id AND p_old.permission_code='table:manage'
JOIN `t_permission` p_new ON p_new.permission_code='table:operate';

INSERT INTO `t_api_permission` (`method`,`path_pattern`,`permission_code`) VALUES
('*','/admin/announcement/list','announcement:view|announcement:manage'),
('*','/admin/announcement/get','announcement:view|announcement:manage'),
('*','/cashier/table/open','cashier:operate|table:operate'),
('*','/cashier/table/merge','cashier:operate|table:operate'),
('*','/cashier/table/transfer','cashier:operate|table:operate'),
('*','/cashier/table/clear','cashier:operate|table:operate')
ON DUPLICATE KEY UPDATE `permission_code`=VALUES(`permission_code`),`method`='*';
