-- KDS 抓串闸门：未抓串前烤制屏不展示待做；抓串屏 picked 后再分流
-- 执行前需已有 t_kds_ticket / t_kds_shop_config（db_migration_kds.sql）

ALTER TABLE `t_kds_ticket`
    ADD COLUMN `skewer_picked` tinyint NOT NULL DEFAULT 0 COMMENT '0待抓串 1已抓串可上烤制屏' AFTER `item_status`,
    ADD COLUMN `skewer_picked_at` datetime DEFAULT NULL COMMENT '抓串完成时间' AFTER `skewer_picked`;

ALTER TABLE `t_kds_shop_config`
    ADD COLUMN `skewer_gate` tinyint NOT NULL DEFAULT 1 COMMENT '1先抓串再分流烤制屏 0直连烤制屏' AFTER `auto_push_on_create`;

-- 已在制作/完成的历史工单视为已抓串，避免升级后烤制屏空白
UPDATE `t_kds_ticket` SET `skewer_picked` = 1 WHERE `item_status` IN (1, 2);
