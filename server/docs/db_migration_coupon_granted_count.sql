-- t_coupon：记录已向用户发放的张数（与 t_user_coupon 成功写入条数一致）
-- 执行后可选：按历史用户券回填（首次上线建议执行）

ALTER TABLE `t_coupon`
  ADD COLUMN `granted_count` int NOT NULL DEFAULT 0 COMMENT '已发放张数（写入 t_user_coupon 累计）' AFTER `stock`;

-- 回填历史数据（可按需注释跳过）
UPDATE `t_coupon` c
INNER JOIN (
  SELECT `coupon_id`, COUNT(*) AS cnt FROM `t_user_coupon` GROUP BY `coupon_id`
) t ON t.`coupon_id` = c.`id`
SET c.`granted_count` = t.cnt;
