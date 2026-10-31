package com.lanf.payment;

/**
 * 支付模块业务错误码（HTTP 仍为 200，body.code 区分）。
 */
public final class PaymentErrorCodes {

    /** 线上支付总开关关闭 */
    public static final int ONLINE_PAY_DISABLED = 40201;
    /** 单渠道关闭 */
    public static final int CHANNEL_DISABLED = 40202;
    /** 未配置可用微信支付商户 */
    public static final int MERCHANT_NOT_CONFIGURED = 40203;

    private PaymentErrorCodes() {
    }
}
