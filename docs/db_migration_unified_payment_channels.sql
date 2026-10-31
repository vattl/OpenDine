-- 统一支付渠道：线上（微信/支付宝/余额/组合）与线下（微信/支付宝收款码）
-- 执行顺序：已执行 docs/db_migration_payment_module.sql 的数据库可直接执行本脚本。

DROP PROCEDURE IF EXISTS `_patch_payment_combined_enabled`;
DELIMITER //
CREATE PROCEDURE `_patch_payment_combined_enabled`()
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 't_payment_capability'
          AND COLUMN_NAME = 'combined_enabled'
    ) THEN
        ALTER TABLE `t_payment_capability`
            ADD COLUMN `combined_enabled` TINYINT NOT NULL DEFAULT 1
                COMMENT '线上组合支付开关'
                AFTER `balance_enabled`;
    END IF;
END //
DELIMITER ;
CALL `_patch_payment_combined_enabled`();
DROP PROCEDURE IF EXISTS `_patch_payment_combined_enabled`;

-- t_payment_method 仅作为支付方式主数据；订单实际落库中文名由后端统一目录规范化。
INSERT IGNORE INTO `t_payment_method` (`shop_id`, `code`, `name`, `sort_order`, `enabled`) VALUES
  (NULL, 'online_wechat', '微信支付', 10, 1),
  (NULL, 'online_alipay', '支付宝支付', 20, 1),
  (NULL, 'online_balance', '余额支付', 30, 1),
  (NULL, 'online_combined', '组合支付', 40, 1),
  (NULL, 'offline_wechat_qr', '微信收款码', 50, 1),
  (NULL, 'offline_alipay_qr', '支付宝收款码', 60, 1);
