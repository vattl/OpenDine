-- 一次性全表纠偏：将 t_user.balance 重写为 principal_balance + gift_balance（两位小数）
-- 用于修复历史脏数据（如 balance 为负但与本金/赠送列不一致）。执行前请备份库。

UPDATE `t_user`
SET `balance` = ROUND(IFNULL(`principal_balance`, 0) + IFNULL(`gift_balance`, 0), 2);
