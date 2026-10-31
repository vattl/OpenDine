package com.lanf.constant;

/**
 * 微信支付统一下单「夜间九折」相关项在 {@code t_system_config.config_key} 中的键名。
 * 运营后台通过 {@code /admin/config/wechat-prepay-ninefold} 读写，小程序可读 {@code /config/wechat-prepay-ninefold}。
 */
public interface WeChatPrepayNineFoldConfigKeys {

    String ENABLED = "wechat.prepay.ninefold.enabled";
    /** 支付倍率，如 0.9 表示九折（实付 = 券后应付 × 倍率） */
    String PAY_RATE = "wechat.prepay.ninefold.payRate";
    /** 券后应付满该金额（元）才允许叠九折 */
    String MIN_BASE_YUAN = "wechat.prepay.ninefold.minBaseYuan";
    /** 生效时段起点，北京时间 HH:mm */
    String TIME_START = "wechat.prepay.ninefold.timeStart";
    /** 生效时段终点，北京时间 HH:mm（含） */
    String TIME_END = "wechat.prepay.ninefold.timeEnd";
    /** 判断时段所用的时区 ID，如 Asia/Shanghai */
    String ZONE_ID = "wechat.prepay.ninefold.zoneId";
    /**
     * 适用就餐方式 JSON 数组，如 {@code ["堂食"]}；取值：堂食、打包、外卖（与 {@code t_order.dineInOrTakeOut} 一致）。
     */
    String ELIGIBLE_DINING_TYPES = "wechat.prepay.ninefold.eligibleDiningTypes";
}
