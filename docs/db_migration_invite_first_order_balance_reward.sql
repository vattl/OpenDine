-- 邀请好友：被邀请人首单支付成功后，按实付比例给邀请人发放余额（幂等字段 + 系统开关）
-- 执行一次即可；与 InviteFirstOrderRewardConfigKeys、t_invite_record 扩展列一致。

ALTER TABLE `t_invite_record`
    ADD COLUMN `first_order_reward_amount` DECIMAL(12, 2) NULL DEFAULT NULL COMMENT '首单余额奖励金额(元)，整数元四舍五入' AFTER `reward_time`,
    ADD COLUMN `first_order_reward_time` DATETIME NULL DEFAULT NULL COMMENT '首单余额奖励发放时间' AFTER `first_order_reward_amount`,
    ADD COLUMN `first_order_no` VARCHAR(64) NULL DEFAULT NULL COMMENT '触发首单奖励的订单号' AFTER `first_order_reward_time`;

INSERT INTO `t_system_config` (`config_key`, `config_value`, `remark`) VALUES
    ('invite.reward.first_order.enabled', 'false', '邀请好友：被邀请人首单支付成功后给邀请人余额奖励开关'),
    ('invite.reward.first_order.percent', '5', '邀请好友：奖励=实付(元)×该比例(%)')
ON DUPLICATE KEY UPDATE `remark` = VALUES(`remark`);
