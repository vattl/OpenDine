-- ============================================================
-- 门店营业流程强制开关：关门时强制交班 / 强制日结
-- 说明：
--   shift_required=1  → 打烊时存在进行中班次则拦截（可 force=1 由老板/店长跳过）
--   settle_required=1 → 打烊时当日营业日未日结则拦截（可 force=1 由老板/店长跳过）
-- 幂等：与 db_migration_shop_ordering_flags.sql 同风格（information_schema 检查，可重复执行）。
-- 默认 0（不强制），老板可在门店设置中按店开启。
-- ============================================================
DROP PROCEDURE IF EXISTS `p_shop_add_settle_flow_flags`;
DELIMITER $$
CREATE PROCEDURE `p_shop_add_settle_flow_flags`()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_shop' AND COLUMN_NAME = 'shift_required'
    ) THEN
        ALTER TABLE `t_shop`
            ADD COLUMN `shift_required` tinyint NOT NULL DEFAULT 0
            COMMENT '关门强制交班：0关 1开' AFTER `ordering_review`;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_shop' AND COLUMN_NAME = 'settle_required'
    ) THEN
        ALTER TABLE `t_shop`
            ADD COLUMN `settle_required` tinyint NOT NULL DEFAULT 0
            COMMENT '关门强制日结：0关 1开' AFTER `shift_required`;
    END IF;
END$$
DELIMITER ;
CALL `p_shop_add_settle_flow_flags`();
DROP PROCEDURE IF EXISTS `p_shop_add_settle_flow_flags`;
