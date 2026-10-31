-- 仅创建 t_region、t_admin_region（不含 t_shop.region_id）
-- 适用：已执行 docs/db_migration_shop_region_id.sql、但尚未跑完整 P3 的库。
-- 全量 P3 请用 docs/db_migration_admin_region.sql（若本文件已执行，全量脚本里 ALTER t_shop 可能重复，跳过即可）。

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `t_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(32) NOT NULL COMMENT '区域编码（唯一）',
  `name` varchar(64) NOT NULL COMMENT '区域名称',
  `parent_id` int NULL DEFAULT NULL COMMENT '父区域ID，可空',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_region_code` (`code`),
  KEY `idx_region_parent` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='区域主数据';

CREATE TABLE IF NOT EXISTS `t_admin_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL COMMENT '管理员ID，t_admin.id',
  `region_id` int NOT NULL COMMENT '区域ID，t_region.id',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_region` (`admin_id`, `region_id`),
  KEY `idx_region` (`region_id`),
  CONSTRAINT `fk_ar_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `fk_ar_region` FOREIGN KEY (`region_id`) REFERENCES `t_region` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='管理员-区域绑定';
