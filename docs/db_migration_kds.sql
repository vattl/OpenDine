-- KDS 厨房显示模块（v2）— 仅新增表，不修改 t_order / t_order_detail
-- 执行前请备份。详见 docs/kds_module_functional_requirements.md

-- 档口/分屏
CREATE TABLE IF NOT EXISTS `t_kds_station` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `name` varchar(64) NOT NULL COMMENT '显示名',
  `code` varchar(32) NOT NULL COMMENT '同店唯一编码，如 MEAT',
  `screen_tag` varchar(32) NOT NULL COMMENT 'skewer_aggregate|meat_grill|veg_grill|seafood_special|expedition',
  `sort` int NOT NULL DEFAULT 0,
  `enabled` tinyint NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_station_shop_code` (`shop_id`, `code`),
  UNIQUE KEY `uk_kds_station_shop_tag` (`shop_id`, `screen_tag`),
  KEY `idx_kds_station_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 档口/分屏';

-- 分类 cid → 档口
CREATE TABLE IF NOT EXISTS `t_kds_station_category` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `station_id` bigint NOT NULL,
  `cid` varchar(64) NOT NULL COMMENT 't_category 主键字符串',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_sc_station_cid` (`station_id`, `cid`),
  KEY `idx_kds_sc_cid` (`cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 分类绑档口';

-- 菜品 → screen_tag（优先于分类）
CREATE TABLE IF NOT EXISTS `t_kds_dish_screen` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `dish_id` int NOT NULL COMMENT 't_dish.id',
  `screen_tag` varchar(32) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_dish_screen` (`shop_id`, `dish_id`),
  KEY `idx_kds_dish_screen_tag` (`shop_id`, `screen_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 菜品绑屏';

-- 门店 KDS 配置
CREATE TABLE IF NOT EXISTS `t_kds_shop_config` (
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `kds_mode` varchar(16) NOT NULL DEFAULT 'print_only' COMMENT 'print_only|kds_only|both',
  `sync_legacy_rece` tinyint NOT NULL DEFAULT 1 COMMENT '划菜是否回写 order_rece',
  `auto_push_on_create` tinyint NOT NULL DEFAULT 1 COMMENT '下单即推厨显',
  `default_screen_tag` varchar(32) DEFAULT 'meat_grill',
  `sla_minutes` int NOT NULL DEFAULT 10,
  `archive_hours` int NOT NULL DEFAULT 2 COMMENT '已完成归档小时数',
  `lack_sets_sold_out` tinyint NOT NULL DEFAULT 0 COMMENT '缺货上报是否置 sold_out',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 门店配置';

-- 厨显设备
CREATE TABLE IF NOT EXISTS `t_kds_device` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `station_id` bigint DEFAULT NULL,
  `screen_tag` varchar(32) NOT NULL,
  `device_code` varchar(64) NOT NULL,
  `device_name` varchar(64) DEFAULT NULL,
  `device_token` varchar(128) DEFAULT NULL,
  `last_heartbeat_at` datetime DEFAULT NULL,
  `enabled` tinyint NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_device_code` (`device_code`),
  KEY `idx_kds_device_shop` (`shop_id`, `screen_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 厨显设备';

-- 厨显工单（单品 × 档口）
CREATE TABLE IF NOT EXISTS `t_kds_ticket` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `station_id` bigint NOT NULL,
  `screen_tag` varchar(32) NOT NULL,
  `order_id` int NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `detail_id` int NOT NULL COMMENT 't_order_detail.id',
  `item_status` tinyint NOT NULL DEFAULT 0 COMMENT '0待制作 1制作中 2已完成 3已退菜',
  `rush_flag` tinyint NOT NULL DEFAULT 0,
  `order_number_snapshot` int DEFAULT NULL,
  `archived` tinyint NOT NULL DEFAULT 0,
  `void_reason` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `accepted_at` datetime DEFAULT NULL,
  `done_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_ticket_detail_station` (`detail_id`, `station_id`),
  KEY `idx_kds_ticket_shop_screen_status` (`shop_id`, `screen_tag`, `item_status`, `archived`),
  KEY `idx_kds_ticket_order` (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 厨显工单';

-- 整单厨显状态
CREATE TABLE IF NOT EXISTS `t_kds_order` (
  `order_id` int NOT NULL COMMENT 't_order.id',
  `shop_id` int NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `kds_order_status` tinyint NOT NULL DEFAULT 10 COMMENT '10/20/30/40/90',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_id`),
  KEY `idx_kds_order_shop_status` (`shop_id`, `kds_order_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 整单厨显状态';

-- 抓串已抓记录
CREATE TABLE IF NOT EXISTS `t_kds_skewer_pick` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `dish_name` varchar(100) NOT NULL,
  `quantity_picked` int NOT NULL DEFAULT 0,
  `unit` varchar(11) DEFAULT NULL,
  `picked_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_skewer_pick_shop_time` (`shop_id`, `picked_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 抓串已抓记录';

-- 离线同步幂等
CREATE TABLE IF NOT EXISTS `t_kds_sync_dedup` (
  `client_id` varchar(64) NOT NULL,
  `shop_id` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 客户端幂等键';

-- 为已有门店插入默认 KDS 配置（仅打印，与现网一致）
INSERT IGNORE INTO `t_kds_shop_config` (`shop_id`, `kds_mode`, `sync_legacy_rece`, `auto_push_on_create`, `default_screen_tag`, `sla_minutes`, `archive_hours`)
SELECT `id`, 'print_only', 1, 1, 'meat_grill', 10, 2 FROM `t_shop`;
