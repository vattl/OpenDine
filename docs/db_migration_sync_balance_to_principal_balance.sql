-- 将当前 t_user.balance 数值同步写入 t_user.principal_balance（数据迁移 / 补数）
--
-- 前置条件：
--   1. 已存在列 principal_balance（若尚未建列，请先执行 db_migration_user_principal_balance.sql 中的 ALTER ADD COLUMN）。
--   2. 本脚本仅做「balance → principal_balance」复制，不修改 balance、gift_balance。
--
-- 语义说明：
--   - 适用于当前库里 balance 存的是「本金」、尚未单独维护 principal_balance 的历史数据。
--   - 若你确认 balance 已是「总余额 = 本金 + 赠送金」，则不应整列复制到本金，请改用下方注释中的【总余额拆本金】语句。

UPDATE `t_user`
SET `principal_balance` = ROUND(IFNULL(`balance`, 0), 2);

-- 【可选】若 balance 为总余额、且 gift_balance 已正确维护，用本金 = 总额 - 赠送金（请先注释掉上面整条 UPDATE，再执行下面这条）：
-- UPDATE `t_user`
-- SET `principal_balance` = ROUND(GREATEST(0, IFNULL(`balance`, 0) - IFNULL(`gift_balance`, 0)), 2);
