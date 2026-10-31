-- 门店菜品库存跟踪持久标志：修复「库存扣到 0 后退菜/取消单无法回退库存」
-- 背景：旧逻辑用当前 stock 值 + onsale 推断是否跟踪库存（stock=0 且在售视为未启用），
--       有限库存被扣减到 0 后该推断失效，退菜回退被静默跳过。
-- 执行前请备份。

ALTER TABLE `t_dish_shop`
    ADD COLUMN `stock_enabled` tinyint NOT NULL DEFAULT 0
        COMMENT '是否启用库存跟踪（持久标志，不随库存值变化）：1 跟踪（扣减/回退）；0 不限量或未启用'
        AFTER `stock`;

-- 回填：stock>0 的有限库存，或 stock=0 且已售罄（表明曾被扣减到 0）的行，视为已启用跟踪。
-- stock=0 且 sold_out=0 保留旧兼容语义（未启用库存）；stock<0 或 NULL 为不限量。
UPDATE `t_dish_shop`
SET `stock_enabled` = 1
WHERE `stock` IS NOT NULL AND `stock` >= 0
  AND (`stock` > 0 OR COALESCE(`sold_out`, 0) = 1);
