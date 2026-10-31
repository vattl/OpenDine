-- 用户账户：赠送金列 gift_balance（与本金分账）；总展示余额见 balance，本金见 principal_balance（需执行 db_migration_user_principal_balance.sql）
ALTER TABLE `t_user`
    ADD COLUMN `gift_balance` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '赠送金余额(元)，与 balance 本金分开' AFTER `balance`;

-- 余额支付时从本金/赠送金账户扣款明细（与 pay_amount_balance 一致：principal+wallet_gift）
ALTER TABLE `t_order`
    ADD COLUMN `balance_pay_principal` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '余额支付从本金扣(元)' AFTER `pay_amount_balance`,
    ADD COLUMN `balance_pay_gift_wallet` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '余额支付从赠送金账户扣(元)' AFTER `balance_pay_principal`;
