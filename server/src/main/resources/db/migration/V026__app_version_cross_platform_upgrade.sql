-- V026: Cross-platform app version upgrade for iOS, Android, and Windows

CREATE TABLE IF NOT EXISTS `t_admin_app_version` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `platform` varchar(32) NOT NULL,
  `channel` varchar(32) NOT NULL DEFAULT 'mobile',
  `latest` varchar(32) NOT NULL,
  `version_code` int NOT NULL DEFAULT 0 COMMENT '数字版本号(用于数值比较)',
  `min_supported` varchar(32) NOT NULL,
  `force_update` tinyint NOT NULL DEFAULT 0,
  `package_type` varchar(16) NOT NULL DEFAULT 'full' COMMENT '安装包类型: full / patch',
  `install_mode` varchar(32) NOT NULL DEFAULT 'interactive' COMMENT '安装模式: interactive / silent / store_redirect',
  `file_size` bigint NULL DEFAULT NULL COMMENT '安装包大小(字节)',
  `sha256` varchar(64) NULL DEFAULT NULL COMMENT '安装包SHA-256校验和',
  `gray_shop_ids` varchar(1024) NULL DEFAULT NULL COMMENT '灰度门店ID列表',
  `release_notes` text NULL,
  `download_url` varchar(1024) NULL,
  `enabled` tinyint NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_app_version` (`platform`,`channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='跨平台客户端版本策略表';

-- 确保 platform 列长度足够 (支持 windows, desktop, pos_sunmi 等)
ALTER TABLE `t_admin_app_version` MODIFY COLUMN `platform` varchar(32) NOT NULL COMMENT '平台: android | ios | windows | desktop | pos_sunmi';

-- 动态守护补充新增列（兼容已存在旧版 t_admin_app_version 的环境）
DROP PROCEDURE IF EXISTS `p_add_app_version_col`;
DELIMITER $
$
CREATE PROCEDURE `p_add_app_version_col`(p_col VARCHAR(128), p_def TEXT)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = p_col) THEN
    SET @sql_cmd = CONCAT('ALTER TABLE `t_admin_app_version` ADD COLUMN ', p_def);
    PREPARE stmt FROM @sql_cmd;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END$
$
DELIMITER ;

CALL `p_add_app_version_col`('version_code', '`version_code` int NOT NULL DEFAULT 0 COMMENT ''数字版本号(用于数值比较)'' AFTER `latest`');
CALL `p_add_app_version_col`('package_type', '`package_type` varchar(16) NOT NULL DEFAULT ''full'' COMMENT ''安装包类型: full / patch'' AFTER `force_update`');
CALL `p_add_app_version_col`('install_mode', '`install_mode` varchar(32) NOT NULL DEFAULT ''interactive'' COMMENT ''安装模式: interactive / silent / store_redirect'' AFTER `package_type`');
CALL `p_add_app_version_col`('file_size', '`file_size` bigint NULL DEFAULT NULL COMMENT ''安装包大小(字节)'' AFTER `install_mode`');
CALL `p_add_app_version_col`('sha256', '`sha256` varchar(64) NULL DEFAULT NULL COMMENT ''安装包SHA-256校验和'' AFTER `file_size`');
CALL `p_add_app_version_col`('gray_shop_ids', '`gray_shop_ids` varchar(1024) NULL DEFAULT NULL COMMENT ''灰度门店ID列表'' AFTER `sha256`');

DROP PROCEDURE IF EXISTS `p_add_app_version_col`;

-- 初始化 Windows 桌面收银端、Android 与 iOS 初始版本策略
INSERT INTO `t_admin_app_version`
(`platform`,`channel`,`latest`,`version_code`,`min_supported`,`force_update`,`package_type`,`install_mode`,`file_size`,`sha256`,`release_notes`,`download_url`,`enabled`)
VALUES
('windows','pos','2.1.0',20100,'2.0.0',0,'full','silent',NULL,NULL,'Windows桌面收银端版本发布',NULL,1),
('windows','desktop','2.1.0',20100,'2.0.0',0,'full','silent',NULL,NULL,'Windows运营管理端版本发布',NULL,1),
('android','mobile','2.1.0',20100,'2.0.0',0,'full','interactive',NULL,NULL,'移动运营端Android版本发布',NULL,1),
('ios','mobile','2.1.0',20100,'2.0.0',0,'full','store_redirect',NULL,NULL,'移动运营端iOS版本发布',NULL,1)
ON DUPLICATE KEY UPDATE
  `install_mode` = VALUES(`install_mode`),
  `version_code` = CASE WHEN `version_code` = 0 THEN VALUES(`version_code`) ELSE `version_code` END;
