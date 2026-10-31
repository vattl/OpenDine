-- ==============================================================================
-- 跨平台客户端版本更新控制中心数据库迁移脚本 (v1.2.302)
-- 支持 Windows 收银端、Windows 桌面端、Android 移动端/商米POS 以及 iOS 移动端
-- 幂等设计：可安全多次重复执行
-- ==============================================================================

-- 1. 创建客户端版本策略表（若不存在）
CREATE TABLE IF NOT EXISTS `t_admin_app_version` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `platform` varchar(32) NOT NULL COMMENT '平台: android | ios | windows | desktop | pos_sunmi',
  `channel` varchar(32) NOT NULL DEFAULT 'mobile' COMMENT '渠道标识: pos / mobile / desktop',
  `latest` varchar(32) NOT NULL COMMENT '最新语义化版本号, 如 2.1.2',
  `version_code` int NOT NULL DEFAULT 0 COMMENT '数字构建版本号(用于数值比较), 如 209',
  `min_supported` varchar(32) NOT NULL COMMENT '最低支持版本号, 如 2.0.0',
  `force_update` tinyint NOT NULL DEFAULT 0 COMMENT '是否强制升级: 1=强制, 0=可选',
  `package_type` varchar(16) NOT NULL DEFAULT 'full' COMMENT '安装包类型: full / wgt / diff / exe / msi / apk',
  `install_mode` varchar(32) NOT NULL DEFAULT 'interactive' COMMENT '安装模式: interactive(交互安装) / silent(静默安装) / store_redirect(应用市场跳转)',
  `file_size` bigint NULL DEFAULT NULL COMMENT '安装包大小(字节数)',
  `sha256` varchar(64) NULL DEFAULT NULL COMMENT '安装包 SHA-256 完整性哈希校验值',
  `gray_shop_ids` varchar(1024) NULL DEFAULT NULL COMMENT '灰度门店ID列表(逗号分隔，如 1,2,5)',
  `release_notes` text NULL COMMENT '版本更新说明/Changelog',
  `download_url` varchar(1024) NULL COMMENT '安装包下载地址或应用商店页面链接',
  `enabled` tinyint NOT NULL DEFAULT 1 COMMENT '是否启用: 1=启用, 0=禁用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_app_version` (`platform`,`channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='跨平台客户端版本策略表';

-- 2. 若旧表已存在，扩展 platform 长度
ALTER TABLE `t_admin_app_version` MODIFY COLUMN `platform` varchar(32) NOT NULL COMMENT '平台: android | ios | windows | desktop | pos_sunmi';

-- 3. 动态检查并补充新增列（兼容旧版环境）
SET @has_version_code := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = 'version_code'
);
SET @sql := IF(@has_version_code = 0,
  'ALTER TABLE `t_admin_app_version` ADD COLUMN `version_code` int NOT NULL DEFAULT 0 COMMENT ''数字构建版本号(用于数值比较)'' AFTER `latest`',
  'SELECT ''version_code column exists'' AS msg');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_package_type := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = 'package_type'
);
SET @sql := IF(@has_package_type = 0,
  'ALTER TABLE `t_admin_app_version` ADD COLUMN `package_type` varchar(16) NOT NULL DEFAULT ''full'' COMMENT ''安装包类型: full / patch'' AFTER `force_update`',
  'SELECT ''package_type column exists'' AS msg');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_install_mode := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = 'install_mode'
);
SET @sql := IF(@has_install_mode = 0,
  'ALTER TABLE `t_admin_app_version` ADD COLUMN `install_mode` varchar(32) NOT NULL DEFAULT ''interactive'' COMMENT ''安装模式: interactive / silent / store_redirect'' AFTER `package_type`',
  'SELECT ''install_mode column exists'' AS msg');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_file_size := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = 'file_size'
);
SET @sql := IF(@has_file_size = 0,
  'ALTER TABLE `t_admin_app_version` ADD COLUMN `file_size` bigint NULL DEFAULT NULL COMMENT ''安装包大小(字节)'' AFTER `install_mode`',
  'SELECT ''file_size column exists'' AS msg');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_sha256 := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = 'sha256'
);
SET @sql := IF(@has_sha256 = 0,
  'ALTER TABLE `t_admin_app_version` ADD COLUMN `sha256` varchar(64) NULL DEFAULT NULL COMMENT ''安装包SHA-256校验和'' AFTER `file_size`',
  'SELECT ''sha256 column exists'' AS msg');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_gray_shop_ids := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_admin_app_version' AND COLUMN_NAME = 'gray_shop_ids'
);
SET @sql := IF(@has_gray_shop_ids = 0,
  'ALTER TABLE `t_admin_app_version` ADD COLUMN `gray_shop_ids` varchar(1024) NULL DEFAULT NULL COMMENT ''灰度门店ID列表'' AFTER `sha256`',
  'SELECT ''gray_shop_ids column exists'' AS msg');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 4. 写入/更新 Windows (pos / desktop)、Android、iOS 初始策略
INSERT INTO `t_admin_app_version`
(`platform`,`channel`,`latest`,`version_code`,`min_supported`,`force_update`,`package_type`,`install_mode`,`file_size`,`sha256`,`release_notes`,`download_url`,`enabled`)
VALUES
('windows','pos','2.1.2',209,'2.0.0',0,'full','silent',28186454,'1AF0EF1DF690FA7EDCAE3E87BF553EDBBA45E807E03C59690DCE61235D541676','Windows收银桌面端版本发布\n1. 优化收银界面与交互\n2. 支持静默下载升级与完整性哈希校验','https://www.laofei.com.cn/admin/app/packages/windows/laofei-cashier-windows-x64-v2.1.2+209-20261019-0137.zip',1),
('windows','desktop','2.1.0',20100,'2.0.0',0,'full','silent',NULL,NULL,'Windows运营管理端版本发布',NULL,1),
('android','mobile','2.1.0',20100,'2.0.0',0,'full','interactive',NULL,NULL,'移动运营端Android版本发布',NULL,1),
('ios','mobile','2.1.0',20100,'2.0.0',0,'full','store_redirect',NULL,NULL,'移动运营端iOS版本发布',NULL,1)
ON DUPLICATE KEY UPDATE
  `latest` = VALUES(`latest`),
  `version_code` = VALUES(`version_code`),
  `min_supported` = VALUES(`min_supported`),
  `install_mode` = VALUES(`install_mode`),
  `package_type` = VALUES(`package_type`),
  `file_size` = COALESCE(VALUES(`file_size`), `file_size`),
  `sha256` = COALESCE(VALUES(`sha256`), `sha256`),
  `release_notes` = VALUES(`release_notes`),
  `download_url` = COALESCE(VALUES(`download_url`), `download_url`);
