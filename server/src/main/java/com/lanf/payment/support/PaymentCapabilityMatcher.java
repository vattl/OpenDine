package com.lanf.payment.support;

import com.lanf.payment.service.PaymentCapabilityService.ResolvedCapability;
import org.springframework.util.StringUtils;

import java.util.Locale;

/**
 * 支付能力与渠道开关匹配器。
 * 支持直接传入数据库字段名（下划线/驼峰）、API 响应字段名、JSON 路径（如 clients.cashier.channels.wechat）及业务中文名进行判定，
 * 无需调用方预先进行特定枚举转换与硬编码映射。
 */
public final class PaymentCapabilityMatcher {

    private PaymentCapabilityMatcher() {
    }

    /**
     * 判断指定的支付能力或渠道在当前门店配置下是否开启生效。
     *
     * @param r   已解析的门店能力快照
     * @param key 字段名、响应路径、渠道代码或中文别名
     * @return true-开启生效，false-未开启或不匹配
     */
    public static boolean isMatchEnabled(ResolvedCapability r, String key) {
        if (r == null || !StringUtils.hasText(key)) {
            return false;
        }

        String raw = key.trim();
        String lower = raw.toLowerCase(Locale.ROOT);

        // 1. 先进行精确路径/标准名匹配
        switch (lower) {
            // 现金
            case "cash":
            case "cash_payment":
            case "offline_cash":
            case "现金":
            case "cashier.cash":
            case "cashier_cash":
            case "clients.cashier.channels.cash":
                return r.cashierPayEnabled;

            // 收银端-微信支付
            case "online_wechat":
            case "wechat":
            case "wechat_pay":
            case "wxpay":
            case "微信":
            case "微信支付":
            case "cashier_wechat":
            case "cashier_wechat_enabled":
            case "cashierwechatenabled":
            case "cashier.wechat":
            case "cashier.channels.wechat":
            case "clients.cashier.channels.wechat":
            case "clients.cashier.effectivechannels.wechat":
                return r.cashierPayEnabled && r.cashierWechatEnabled;

            // 收银端-支付宝支付
            case "online_alipay":
            case "alipay":
            case "alipay_pay":
            case "支付宝":
            case "支付宝支付":
            case "cashier_alipay":
            case "cashier_alipay_enabled":
            case "cashieralipayenabled":
            case "cashier.alipay":
            case "cashier.channels.alipay":
            case "clients.cashier.channels.alipay":
            case "clients.cashier.effectivechannels.alipay":
                return r.cashierPayEnabled && r.cashierAlipayEnabled;

            // 收银端-余额支付
            case "online_balance":
            case "balance":
            case "balance_pay":
            case "余额":
            case "余额支付":
            case "cashier_balance":
            case "cashier_balance_enabled":
            case "cashierbalanceenabled":
            case "cashier.balance":
            case "cashier.channels.balance":
            case "clients.cashier.channels.balance":
            case "clients.cashier.effectivechannels.balance":
                return r.cashierPayEnabled && r.cashierBalanceEnabled;

            // 收银端-组合支付
            case "online_combined":
            case "combined":
            case "combination":
            case "combined_pay":
            case "组合支付":
            case "cashier_combined":
            case "cashier_combined_enabled":
            case "cashiercombinedenabled":
            case "cashier.combined":
            case "cashier.channels.combined":
            case "clients.cashier.channels.combined":
            case "clients.cashier.effectivechannels.combined":
                return isCombinedEnabled(r);

            // 线下收款码-微信
            case "offline_wechat_qr":
            case "offline_wechat":
            case "offline_wechat_qr_auto":
            case "offline_wechat_auto":
            case "wechat_qr":
            case "wechat_qr_auto":
            case "微信收款码":
            case "微信收款码自动":
            case "微信收款码(自动)":
            case "微信收款码（自动）":
            case "微信码":
            case "微信码自动":
            case "offline_collect_wechat":
            case "offlinecollect.wechat":
            case "channels.offlinecollect.wechat":
                return isOfflineWechatEnabled(r);

            // 线下收款码-支付宝
            case "offline_alipay_qr":
            case "offline_alipay":
            case "offline_alipay_qr_auto":
            case "offline_alipay_auto":
            case "alipay_qr":
            case "alipay_qr_auto":
            case "支付宝收款码":
            case "支付宝收款码自动":
            case "支付宝收款码(自动)":
            case "支付宝收款码（自动）":
            case "支付宝码":
            case "支付宝码自动":
            case "offline_collect_alipay":
            case "offlinecollect.alipay":
            case "channels.offlinecollect.alipay":
                return isOfflineAlipayEnabled(r);

            // 小程序端-微信支付
            case "mini_program_wechat":
            case "mini_program_wechat_enabled":
            case "miniprogramwechatenabled":
            case "miniprogram.wechat":
            case "mini.wechat":
            case "clients.miniprogram.channels.wechat":
            case "clients.miniprogram.effectivechannels.wechat":
                return r.miniProgramPayEnabled && r.miniProgramWechatEnabled;

            // 小程序端-余额支付
            case "mini_program_balance":
            case "mini_program_balance_enabled":
            case "miniprogrambalanceenabled":
            case "miniprogram.balance":
            case "mini.balance":
            case "clients.miniprogram.channels.balance":
            case "clients.miniprogram.effectivechannels.balance":
                return r.miniProgramPayEnabled && r.miniProgramBalanceEnabled;

            // 总开关
            case "cashier_pay_enabled":
            case "cashierpayenabled":
            case "cashier.enabled":
            case "clients.cashier.enabled":
                return r.cashierPayEnabled;

            case "mini_program_pay_enabled":
            case "miniprogrampayenabled":
            case "miniprogram.enabled":
            case "clients.miniprogram.enabled":
                return r.miniProgramPayEnabled;

            case "offline_collect_enabled":
            case "offlinecollectenabled":
            case "offlinecollect.enabled":
            case "channels.offlinecollect.enabled":
                return r.offlineCollectEnabled;

            default:
                break;
        }

        // 2. 泛化模糊归一化匹配（支持驼峰转小写、去除特殊符号与冗余节点前缀）
        String clean = lower
                .replace("-", "")
                .replace("_", "")
                .replace(".", "")
                .replace("clients", "")
                .replace("channels", "")
                .replace("effective", "")
                .replace("enabled", "");

        switch (clean) {
            case "cash":
            case "cashiercash":
            case "现金":
                return r.cashierPayEnabled;
            case "cashierwechat":
            case "cashierwechatpay":
            case "onlinewechat":
            case "wechatpay":
            case "微信支付":
                return r.cashierPayEnabled && r.cashierWechatEnabled;
            case "cashieralipay":
            case "cashieralipaypay":
            case "onlinealipay":
            case "alipaypay":
            case "支付宝支付":
                return r.cashierPayEnabled && r.cashierAlipayEnabled;
            case "cashierbalance":
            case "cashierbalancepay":
            case "onlinebalance":
            case "balancepay":
            case "余额支付":
                return r.cashierPayEnabled && r.cashierBalanceEnabled;
            case "cashiercombined":
            case "cashiercombinedpay":
            case "onlinecombined":
            case "combinedpay":
            case "组合支付":
                return isCombinedEnabled(r);
            case "offlinewechat":
            case "offlinewechatqr":
            case "offlinewechatqrauto":
            case "offlinewechatauto":
            case "offlinecollectwechat":
            case "wechatqr":
            case "wechatqrauto":
            case "微信收款码":
            case "微信收款码自动":
                return isOfflineWechatEnabled(r);
            case "offlinealipay":
            case "offlinealipayqr":
            case "offlinealipayqrauto":
            case "offlinealipayauto":
            case "offlinecollectalipay":
            case "alipayqr":
            case "alipayqrauto":
            case "支付宝收款码":
            case "支付宝收款码自动":
                return isOfflineAlipayEnabled(r);
            case "miniprogramwechat":
            case "miniwechat":
                return r.miniProgramPayEnabled && r.miniProgramWechatEnabled;
            case "miniprogrambalance":
            case "minibalance":
                return r.miniProgramPayEnabled && r.miniProgramBalanceEnabled;
            case "cashierpay":
            case "cashier":
                return r.cashierPayEnabled;
            case "miniprogrampay":
            case "miniprogram":
                return r.miniProgramPayEnabled;
            case "offlinecollect":
                return r.offlineCollectEnabled;
            default:
                return false;
        }
    }

    private static boolean isCombinedEnabled(ResolvedCapability r) {
        int enabledCashierCount = 1
                + (r.cashierWechatEnabled ? 1 : 0)
                + (r.cashierAlipayEnabled ? 1 : 0)
                + (r.cashierBalanceEnabled ? 1 : 0);
        return r.cashierPayEnabled && r.cashierCombinedEnabled && enabledCashierCount >= 2;
    }

    // 收银人工收款码使用 cashier_wechat_qr_enabled/cashier_alipay_qr_enabled 独立列；
    // 线上商户支付开关及历史 offlineCollect 列均不参与个人码出码或结账判定。
    private static boolean isOfflineWechatEnabled(ResolvedCapability r) {
        return r.cashierPayEnabled
                && r.cashierWechatQrEnabled;
    }

    private static boolean isOfflineAlipayEnabled(ResolvedCapability r) {
        return r.cashierPayEnabled
                && r.cashierAlipayQrEnabled;
    }
}
