-- 弃用 t_member_account：余额仅使用 t_user.balance
-- 执行 DROP 前如需合并历史余额到用户表，可先执行（按需取消注释）：
-- UPDATE t_user u
-- INNER JOIN t_member_account m ON m.openid = u.openid AND (m.openid IS NOT NULL AND m.openid <> '')
-- SET u.balance = ROUND(IFNULL(u.balance, 0) + IFNULL(m.balance, 0), 2);

DROP TABLE IF EXISTS `t_member_account`;
