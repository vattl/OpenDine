-- 连锁门店独立库存迁移
-- 目标：库存扣减/回退仅使用 t_dish_shop.stock（按门店隔离），不回退 t_dish.stock
-- 建议在低峰期执行，并先备份数据库

SET NAMES utf8mb4;

-- 1) 给已挂店菜品补齐门店库存（空值统一设为 -1 不限量）
UPDATE `t_dish_shop` ds
SET ds.`stock` = -1
WHERE ds.`stock` IS NULL;

-- 2) 门店库存改为非空，默认 -1（不限量）
ALTER TABLE `t_dish_shop`
  MODIFY COLUMN `stock` int NOT NULL DEFAULT -1 COMMENT '门店可售库存；-1 不限量；>=0 为有限库存';

-- 3) 巡检：门店库存必须全部非空
-- SELECT ds.shop_id, ds.dish_id FROM t_dish_shop ds WHERE ds.stock IS NULL;
-- 预期 0 行

