-- 本金单独列：小程序继续读 balance 为「总余额」；principal_balance 为可消费本金；gift_balance 为赠送金。
-- 恒等式：balance = principal_balance + gift_balance
ALTER TABLE `t_user`
    ADD COLUMN `principal_balance` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 COMMENT '本金(元)；balance=principal_balance+gift_balance' AFTER `balance`;

-- 以下二选一执行（勿同时执行两条 UPDATE，避免重复加计）。
--
-- 【A】若此前已按「balance 仅存本金、gift_balance 存赠送金」上线（总额未加进 balance），执行本段纠偏：
UPDATE `t_user` SET
    `principal_balance` = ROUND(IFNULL(`balance`, 0), 2),
    `balance` = ROUND(IFNULL(`balance`, 0) + IFNULL(`gift_balance`, 0), 2);
--
-- 【B】若 balance 已是「本金+赠送」总额，仅补写本金列，执行本段（注释掉上面 A 段后执行）：
-- UPDATE `t_user` SET
--     `principal_balance` = ROUND(GREATEST(0, IFNULL(`balance`, 0) - IFNULL(`gift_balance`, 0)), 2);
