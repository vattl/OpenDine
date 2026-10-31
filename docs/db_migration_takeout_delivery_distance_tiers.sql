-- 外卖配送费：按距离梯度 + 满额免配（需门店与用户地址均有经纬度）
-- 默认：起送 68 元；1-3km 5 元、3-4km 8 元、4-5km 10 元；满 168 元且 5km 内免配送费

ALTER TABLE `t_shop_takeout_config`
  ADD COLUMN `max_delivery_distance_km` decimal(5, 2) NOT NULL DEFAULT 5.00 COMMENT '最远配送距离(公里)，超出不可下单' AFTER `free_delivery_threshold`,
  ADD COLUMN `free_delivery_max_distance_km` decimal(5, 2) NOT NULL DEFAULT 5.00 COMMENT '满额免配送费的最远距离(公里)' AFTER `max_delivery_distance_km`,
  ADD COLUMN `delivery_fee_tiers_json` text NULL COMMENT '距离阶梯运费 JSON，如 [{"toKm":3,"fee":5},{"toKm":4,"fee":8},{"toKm":5,"fee":10}]' AFTER `free_delivery_max_distance_km`;

UPDATE `t_shop_takeout_config`
SET
  `min_order_amount` = 68.00,
  `free_delivery_threshold` = 168.00,
  `max_delivery_distance_km` = 5.00,
  `free_delivery_max_distance_km` = 5.00,
  `delivery_fee_tiers_json` = '[{"toKm":3,"fee":5},{"toKm":4,"fee":8},{"toKm":5,"fee":10}]',
  `remark` = '起送68元；按距离收费：1-3km 5元、3-4km 8元、4-5km 10元；满168元5公里内免配送费'
WHERE `delivery_fee_tiers_json` IS NULL OR `delivery_fee_tiers_json` = '';
