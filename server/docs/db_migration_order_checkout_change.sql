-- 结账找零：客人付现大于现金实收时记录找零金额与找零渠道（wechat/cash/alipay）
ALTER TABLE `t_order`
    ADD COLUMN `checkout_cash_tender` DECIMAL(12, 2) NULL DEFAULT NULL COMMENT '结账客人付现金额(元)，可大于 pay_amount_cash' AFTER `pay_amount_cash`,
    ADD COLUMN `checkout_change_amount` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '找零金额(元)' AFTER `checkout_cash_tender`,
    ADD COLUMN `checkout_change_channel` VARCHAR(16) NULL DEFAULT NULL COMMENT '找零渠道: wechat/cash/alipay' AFTER `checkout_change_amount`;
