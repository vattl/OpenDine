-- 订单明细关联菜品 ID（方案 B：KDS 行透出 dish_id 的前置）
-- 1) 加列与索引
ALTER TABLE `t_order_detail`
    ADD COLUMN `dish_id` int NULL DEFAULT NULL COMMENT 't_dish.id，下单时写入；历史数据按 name 回填' AFTER `cid`,
    ADD INDEX `idx_order_detail_dish`(`dish_id`) USING BTREE;

-- 2) 历史数据按菜名回填（t_dish.name 唯一时直接匹配；重名菜取最小 id，匹配不上留 NULL）
UPDATE `t_order_detail` od
JOIN (
    SELECT `name`, MIN(`id`) AS dish_id
    FROM `t_dish`
    GROUP BY `name`
) d ON d.`name` = od.`name`
SET od.`dish_id` = d.`dish_id`
WHERE od.`dish_id` IS NULL;
