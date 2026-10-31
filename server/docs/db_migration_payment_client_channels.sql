-- 支付渠道按终端独立配置：
-- cashier：微信、支付宝、余额、组合支付
-- mini_program：微信、余额支付
-- NULL 表示未单独配置，运行时回退旧字段或全店模板。

DROP PROCEDURE IF EXISTS `_patch_payment_client_channels`;
DELIMITER //
CREATE PROCEDURE `_patch_payment_client_channels`()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='cashier_pay_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `cashier_pay_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端支付总开关' AFTER `combined_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='cashier_wechat_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `cashier_wechat_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端微信支付' AFTER `cashier_pay_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='cashier_alipay_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `cashier_alipay_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端支付宝支付' AFTER `cashier_wechat_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='cashier_balance_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `cashier_balance_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端余额支付' AFTER `cashier_alipay_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='cashier_combined_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `cashier_combined_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端组合支付' AFTER `cashier_balance_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='mini_program_pay_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `mini_program_pay_enabled` TINYINT NULL DEFAULT NULL COMMENT '微信小程序端支付总开关' AFTER `cashier_combined_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='mini_program_wechat_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `mini_program_wechat_enabled` TINYINT NULL DEFAULT NULL COMMENT '微信小程序端微信支付' AFTER `mini_program_pay_enabled`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_payment_capability' AND COLUMN_NAME='mini_program_balance_enabled') THEN
        ALTER TABLE `t_payment_capability` ADD COLUMN `mini_program_balance_enabled` TINYINT NULL DEFAULT NULL COMMENT '微信小程序端余额支付' AFTER `mini_program_wechat_enabled`;
    END IF;
END //
DELIMITER ;
CALL `_patch_payment_client_channels`();
DROP PROCEDURE IF EXISTS `_patch_payment_client_channels`;

-- 首次迁移保持旧行为；后续由 PUT /admin/payment/capabilities 独立修改。
UPDATE `t_payment_capability`
SET `cashier_pay_enabled` = COALESCE(`cashier_pay_enabled`, `online_pay_enabled`),
    `cashier_wechat_enabled` = COALESCE(`cashier_wechat_enabled`, `wechat_enabled`),
    `cashier_alipay_enabled` = COALESCE(`cashier_alipay_enabled`, `alipay_enabled`),
    `cashier_balance_enabled` = COALESCE(`cashier_balance_enabled`, `balance_enabled`),
    `cashier_combined_enabled` = COALESCE(`cashier_combined_enabled`, `combined_enabled`),
    `mini_program_pay_enabled` = COALESCE(`mini_program_pay_enabled`, `online_pay_enabled`),
    `mini_program_wechat_enabled` = COALESCE(`mini_program_wechat_enabled`, `wechat_enabled`),
    `mini_program_balance_enabled` = COALESCE(`mini_program_balance_enabled`, `balance_enabled`);
