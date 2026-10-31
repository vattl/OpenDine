-- 订单按支付渠道拆分实付金额（元），与 payment_method 互补；未迁移库执行一次即可。

ALTER TABLE `t_order`
    ADD COLUMN `pay_amount_wechat` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '微信支付金额(元)' AFTER `payment_method`,
    ADD COLUMN `pay_amount_alipay` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '支付宝支付金额(元)' AFTER `pay_amount_wechat`,
    ADD COLUMN `pay_amount_balance` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '余额支付金额(元)' AFTER `pay_amount_alipay`,
    ADD COLUMN `pay_amount_gift` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '赠送金支付金额(元)' AFTER `pay_amount_balance`,
    ADD COLUMN `pay_amount_cash` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '现金支付金额(元)' AFTER `pay_amount_gift`;

-- 可选：按既有 payment_method 回填历史成功订单（执行前请备份）
/*
UPDATE `t_order` SET `pay_amount_wechat` = ROUND(IFNULL(`sett_amount`, 0) + IFNULL(`service_fee`, 0) - IFNULL(`discount_amount`, 0) - IFNULL(`refund_amount`, 0), 2)
WHERE `transac_status` = 'success' AND `payment_method` LIKE '%微信%';
UPDATE `t_order` SET `pay_amount_balance` = ROUND(IFNULL(`sett_amount`, 0) + IFNULL(`service_fee`, 0) - IFNULL(`discount_amount`, 0) - IFNULL(`refund_amount`, 0), 2)
WHERE `transac_status` = 'success' AND `payment_method` LIKE '%余额%' AND `payment_method` NOT LIKE '%赠送%';
UPDATE `t_order` SET `pay_amount_gift` = ROUND(IFNULL(`sett_amount`, 0) + IFNULL(`service_fee`, 0) - IFNULL(`discount_amount`, 0) - IFNULL(`refund_amount`, 0), 2)
WHERE `transac_status` = 'success' AND (`payment_method` LIKE '%赠送%' OR `payment_method` LIKE '%赠送金%');
UPDATE `t_order` SET `pay_amount_alipay` = ROUND(IFNULL(`sett_amount`, 0) + IFNULL(`service_fee`, 0) - IFNULL(`discount_amount`, 0) - IFNULL(`refund_amount`, 0), 2)
WHERE `transac_status` = 'success' AND (`payment_method` LIKE '%支付宝%' OR LOWER(`payment_method`) = 'alipay');
UPDATE `t_order` SET `pay_amount_cash` = ROUND(IFNULL(`sett_amount`, 0) + IFNULL(`service_fee`, 0) - IFNULL(`discount_amount`, 0) - IFNULL(`refund_amount`, 0), 2)
WHERE `transac_status` = 'success' AND (`payment_method` IN ('cash', '现金', '现金支付') OR `payment_method` LIKE '%现金%');
*/
