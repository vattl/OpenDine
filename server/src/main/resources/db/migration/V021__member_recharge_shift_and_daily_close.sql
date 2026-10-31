-- WI-006: member recharge attribution and immutable daily-close summary.

ALTER TABLE `t_member_recharge`
  ADD COLUMN `operator_id` INT DEFAULT NULL COMMENT '后台人工充值操作员ID' AFTER `shop_id`,
  ADD COLUMN `drawer_session_id` BIGINT DEFAULT NULL COMMENT '后台人工充值归属钱箱会话ID' AFTER `operator_id`,
  ADD KEY `idx_recharge_drawer_status` (`drawer_session_id`, `status`),
  ADD KEY `idx_recharge_shop_status_pay_time` (`shop_id`, `status`, `pay_time`);

ALTER TABLE `t_daily_close_snapshot`
  ADD COLUMN `cutoff_recharge_id` BIGINT DEFAULT NULL COMMENT '截止会员充值流水最大主键ID' AFTER `cutoff_order_id`,
  ADD COLUMN `member_recharge_gift_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '会员充值赠送额(分)，不计实收' AFTER `member_recharge_fen`,
  ADD COLUMN `member_recharge_count` INT NOT NULL DEFAULT 0 COMMENT '成功会员充值笔数' AFTER `member_recharge_gift_fen`;
