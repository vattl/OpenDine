package com.lanf.constant;

/**
 * 邀请好友「首单支付成功给邀请人余额奖励」在 {@code t_system_config.config_key} 中的键名。
 * 运营后台 {@code /admin/config/invite-first-order-balance-reward}；C 端只读 {@code /config/invite-first-order-balance-reward}。
 */
public interface InviteFirstOrderRewardConfigKeys {

    String ENABLED = "invite.reward.first_order.enabled";
    /** 奖励占实付金额的百分比，如 5 表示 5% */
    String PERCENT = "invite.reward.first_order.percent";
}
