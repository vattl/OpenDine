/*
  P3 区域权限迁移脚本（与 admin_chain_permission_architecture.md 对齐）
  目标：
  1) 新增区域表 t_region
  2) t_shop 增加 region_id
  3) 新增管理员区域绑定表 t_admin_region
*/

SET NAMES utf8mb4;

-- 1) 区域主数据
CREATE TABLE IF NOT EXISTS `t_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(32) NOT NULL COMMENT '区域编码（唯一）',
  `name` varchar(64) NOT NULL COMMENT '区域名称',
  `parent_id` int NULL DEFAULT NULL COMMENT '父区域ID，可空',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_region_code` (`code`),
  KEY `idx_region_parent` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='区域主数据';

-- 2) 门店归属区域
ALTER TABLE `t_shop`
  ADD COLUMN `region_id` int NULL DEFAULT NULL COMMENT '区域ID，关联 t_region.id' AFTER `code`;

ALTER TABLE `t_shop`
  ADD KEY `idx_shop_region` (`region_id`);

-- 可选外键（若历史数据已清洗可开启）
-- ALTER TABLE `t_shop`
--   ADD CONSTRAINT `fk_shop_region` FOREIGN KEY (`region_id`) REFERENCES `t_region` (`id`) ON DELETE SET NULL ON UPDATE RESTRICT;

-- 3) 管理员-区域绑定
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
