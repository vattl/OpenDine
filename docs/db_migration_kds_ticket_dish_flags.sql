-- KDS 工单菜品状态持久化：催 / 超 / 加（多屏同步读库）
-- 执行前请备份

ALTER TABLE `t_kds_ticket`
    ADD COLUMN `add_dish_flag` tinyint NOT NULL DEFAULT 0 COMMENT '加菜标记 0/1' AFTER `rush_flag`,
    ADD COLUMN `overdue_flag` tinyint NOT NULL DEFAULT 0 COMMENT '超时标记 0/1（待做且超 SLA）' AFTER `add_dish_flag`,
    ADD COLUMN `overdue_at` datetime NULL DEFAULT NULL COMMENT '首次标记超时时间' AFTER `overdue_flag`,
    ADD COLUMN `rush_at` datetime NULL DEFAULT NULL COMMENT '催菜时间' AFTER `overdue_at`;

-- 历史工单：按 snapshot 回填加菜标记
UPDATE `t_kds_ticket`
SET `add_dish_flag` = 1
WHERE `order_number_snapshot` IS NOT NULL AND `order_number_snapshot` > 1;

ALTER TABLE `t_kds_ticket`
    ADD KEY `idx_kds_ticket_shop_flags` (`shop_id`, `rush_flag`, `overdue_flag`, `add_dish_flag`);
