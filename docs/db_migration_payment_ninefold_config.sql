-- 夜间九折：按门店隔离（shop_id=0 为全店默认模板，各店可独立开关与规则）
CREATE TABLE IF NOT EXISTS `t_payment_ninefold_config` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `shop_id` INT NOT NULL DEFAULT 0 COMMENT '0=全店默认',
  `enabled` TINYINT NOT NULL DEFAULT 0 COMMENT '夜间九折独立开关',
  `pay_rate` DECIMAL(5,4) NOT NULL DEFAULT 0.9000 COMMENT '实付倍率，0.9=九折',
  `min_base_yuan` DECIMAL(10,2) NOT NULL DEFAULT 60.00 COMMENT '券后满额(元)才叠九折',
  `time_start` VARCHAR(8) NOT NULL DEFAULT '00:30',
  `time_end` VARCHAR(8) NOT NULL DEFAULT '03:00',
  `zone_id` VARCHAR(64) NOT NULL DEFAULT 'Asia/Shanghai',
  `eligible_dining_types` VARCHAR(256) NOT NULL DEFAULT '["堂食"]',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店夜间九折配置';

-- 全店默认：与历史全局规则一致（默认开启、仅堂食）
INSERT IGNORE INTO `t_payment_ninefold_config` (
  `shop_id`, `enabled`, `pay_rate`, `min_base_yuan`, `time_start`, `time_end`, `zone_id`, `eligible_dining_types`
) VALUES (
  0, 1, 0.9000, 60.00, '00:30', '03:00', 'Asia/Shanghai', '["堂食"]'
);
