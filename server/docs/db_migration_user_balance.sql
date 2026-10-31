-- 用户表余额（元），与订单「余额支付」配套；执行一次即可
ALTER TABLE `t_user`
    ADD COLUMN `balance` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '账户余额(元)' AFTER `points`;
