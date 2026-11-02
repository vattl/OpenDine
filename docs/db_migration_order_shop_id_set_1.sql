-- 将 t_order 所有行的 shop_id 设为 1（单店/数据修复用）
-- 前提：已执行 docs/db_diancan_chain_store_patch.sql，t_order 存在 shop_id 列。
-- 多门店环境慎用：会丢失订单与门店的真实对应关系。

SET NAMES utf8mb4;

UPDATE `t_order` SET `shop_id` = 1;

-- 若只想补全空值，可改用：
-- UPDATE `t_order` SET `shop_id` = 1 WHERE `shop_id` IS NULL;
