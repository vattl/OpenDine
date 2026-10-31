-- 优惠券模板新增：适用菜品 ID 白名单（JSON 数组字符串）
-- 说明：为空/NULL 表示不限菜品；非空表示仅允许订单内菜品均命中该列表才可用券

ALTER TABLE `t_coupon`
  ADD COLUMN `apply_dish_ids` varchar(1000) NULL DEFAULT NULL
  COMMENT '适用菜品ID数组（JSON字符串），为空表示不限菜品，如 [1,2,3]'
  AFTER `apply_dining_type`;

