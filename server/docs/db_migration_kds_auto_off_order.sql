-- KDS 厨显整单完成（40）后可选自动清台：将 t_order.order_receiving 置为 off_order
-- 默认 0（关闭）；开启后不影响 kds_order_status（仍为 40，见 v1.2.136）

ALTER TABLE `t_kds_shop_config`
    ADD COLUMN `auto_off_order_on_kds_done` tinyint NOT NULL DEFAULT 0
        COMMENT '1=厨显整单完成时自动置 order_receiving=off_order（清台） 0=不联动'
        AFTER `sync_legacy_rece`;
