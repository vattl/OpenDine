-- C 端营业/评价开关按门店存储（原 OrderController 全局变量改为 t_shop 列）。
-- 可重复执行：仅补充不存在的列。
DROP PROCEDURE IF EXISTS `p_shop_add_ordering_flags`;
DELIMITER $$
CREATE PROCEDURE `p_shop_add_ordering_flags`()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_shop' AND COLUMN_NAME = 'ordering_open'
    ) THEN
        ALTER TABLE `t_shop`
            ADD COLUMN `ordering_open` tinyint NOT NULL DEFAULT 1
            COMMENT 'C端接单营业：1营业 0休息' AFTER `sort_order`;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_shop' AND COLUMN_NAME = 'ordering_review'
    ) THEN
        ALTER TABLE `t_shop`
            ADD COLUMN `ordering_review` tinyint NOT NULL DEFAULT 0
            COMMENT 'C端评价展示：1开 0关' AFTER `ordering_open`;
    END IF;
END$$
DELIMITER ;

CALL `p_shop_add_ordering_flags`();
DROP PROCEDURE IF EXISTS `p_shop_add_ordering_flags`;
