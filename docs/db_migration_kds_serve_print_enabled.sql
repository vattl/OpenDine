-- KDS 待传菜划单后是否打印飞鹅传菜单（按明细逐条）
-- 默认 1（开启，与 v1.2.134 行为一致）；0=关闭

ALTER TABLE `t_kds_shop_config`
    ADD COLUMN `serve_print_enabled` tinyint NOT NULL DEFAULT 1
        COMMENT '1=待传菜划单后打印传菜单 0=不打印'
        AFTER `auto_off_order_on_kds_done`;
