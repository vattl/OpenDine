-- 已有库升级：菜品可售库存独立字段（与 t_dish.quantity 解耦）
-- 执行一次即可；新环境可直接用 db_diancan.sql 建表

ALTER TABLE `t_dish`
  ADD COLUMN `stock` int NULL DEFAULT NULL COMMENT '可售库存份数；NULL 表示不限量；与 quantity 解耦，下单扣减仅更新本列' AFTER `quantity`;
