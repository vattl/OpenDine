-- 外卖模块：用户收货地址、门店外卖开关与费用、订单配送扩展（与 t_order 一对一）
-- 执行前请备份。已有门店会插入默认配置（默认关闭外卖，配送费 0，起送 0）。

CREATE TABLE IF NOT EXISTS `t_user_address` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `openid` varchar(100) NOT NULL COMMENT 't_user.openid',
  `contact_name` varchar(32) DEFAULT NULL,
  `contact_phone` varchar(20) NOT NULL,
  `tag` varchar(20) DEFAULT NULL COMMENT '家/公司/学校等',
  `province` varchar(32) DEFAULT NULL,
  `city` varchar(32) DEFAULT NULL,
  `district` varchar(32) DEFAULT NULL,
  `detail_address` varchar(255) NOT NULL,
  `lng` decimal(10,6) DEFAULT NULL,
  `lat` decimal(10,6) DEFAULT NULL,
  `is_default` tinyint NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_address_openid` (`openid`),
  KEY `idx_user_address_openid_default` (`openid`, `is_default`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='小程序用户收货地址';

CREATE TABLE IF NOT EXISTS `t_shop_takeout_config` (
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `enabled` tinyint NOT NULL DEFAULT 0 COMMENT '1=开启外卖',
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '基础配送费（元）',
  `min_order_amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '起送价（元，按商品小计不含配送费）',
  `free_delivery_threshold` decimal(10,2) DEFAULT NULL COMMENT '满额免配送费；NULL 表示不免',
  `lead_time_minutes` int NOT NULL DEFAULT 30 COMMENT '预计备餐分钟（展示用）',
  `remark` varchar(500) DEFAULT NULL COMMENT '对外说明',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店外卖配置';

CREATE TABLE IF NOT EXISTS `t_takeout_delivery` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `order_id` int NOT NULL COMMENT 't_order.id',
  `order_no` varchar(32) NOT NULL,
  `shop_id` int DEFAULT NULL,
  `user_address_id` bigint DEFAULT NULL COMMENT '下单时选用的 t_user_address.id',
  `receiver_name` varchar(32) DEFAULT NULL,
  `receiver_phone` varchar(20) NOT NULL,
  `address_full` varchar(512) NOT NULL,
  `lng` decimal(10,6) DEFAULT NULL,
  `lat` decimal(10,6) DEFAULT NULL,
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT 0.00,
  `dispatch_status` varchar(24) NOT NULL DEFAULT 'submitted' COMMENT 'submitted|paid|accepted|delivering|completed|cancelled',
  `merchant_remark` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_takeout_order_id` (`order_id`),
  KEY `idx_takeout_shop_status` (`shop_id`, `dispatch_status`),
  KEY `idx_takeout_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='外卖配送扩展（与 dineInOrTakeOut=外卖 的订单绑定）';

INSERT IGNORE INTO `t_shop_takeout_config` (`shop_id`, `enabled`, `delivery_fee`, `min_order_amount`, `free_delivery_threshold`, `lead_time_minutes`, `remark`)
SELECT `id`, 0, 0.00, 0.00, NULL, 30, NULL FROM `t_shop`;
