package com.lanf.payment.support;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * 后端统一支付渠道目录。code 用于接口传输，name 写入 t_order.payment_method。
 */
public final class PaymentChannelCatalog {

    public static final String CASH = "cash";
    public static final String ONLINE_WECHAT = "online_wechat";
    public static final String ONLINE_ALIPAY = "online_alipay";
    public static final String ONLINE_BALANCE = "online_balance";
    public static final String ONLINE_COMBINED = "online_combined";
    public static final String OFFLINE_WECHAT_QR = "offline_wechat_qr";
    public static final String OFFLINE_ALIPAY_QR = "offline_alipay_qr";
    public static final String RECEIVABLE = "receivable";

    public static final String REPORT_WECHAT = "wechat";
    public static final String REPORT_ALIPAY = "alipay";
    public static final String REPORT_WECHAT_QR = "wechat_qr";
    public static final String REPORT_ALIPAY_QR = "alipay_qr";

    public static final String NAME_WECHAT_PAY = "微信支付";
    public static final String NAME_ALIPAY_PAY = "支付宝支付";
    public static final String NAME_BALANCE_PAY = "余额支付";
    public static final String NAME_COMBINED_PAY = "组合支付";
    public static final String NAME_WECHAT_QR = "微信收款码";
    public static final String NAME_ALIPAY_QR = "支付宝收款码";
    public static final String NAME_WECHAT_QR_AUTO = "微信收款码自动";
    public static final String NAME_ALIPAY_QR_AUTO = "支付宝收款码自动";
    public static final String NAME_CASH = "现金";
    public static final String NAME_RECEIVABLE = "挂账";

    private PaymentChannelCatalog() {
    }

    /**
     * 新 code、旧 code、中文名统一为稳定中文落库值；未知自定义方式原样保留。
     */
    public static String normalizePaymentMethod(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            return trimmed;
        }
        String key = trimmed.toLowerCase(Locale.ROOT);
        switch (key) {
            case CASH:
            case "offline_cash":
            case "cash_payment":
            case "cashier.cash":
            case "cashier_cash":
            case "cashiercash":
            case "clients.cashier.channels.cash":
            case NAME_CASH:
                return NAME_CASH;
            case ONLINE_WECHAT:
            case "wechat":
            case "wechat_pay":
            case "wxpay":
            case "微信":
            case "cashier_wechat":
            case "cashier_wechat_enabled":
            case "cashierwechatenabled":
            case "cashier.wechat":
            case "cashier.channels.wechat":
            case "clients.cashier.channels.wechat":
            case "clients.cashier.effectivechannels.wechat":
            case "mini_program_wechat":
            case "mini_program_wechat_enabled":
            case "miniprogramwechatenabled":
            case "miniprogram.wechat":
            case "clients.miniprogram.channels.wechat":
            case NAME_WECHAT_PAY:
                return NAME_WECHAT_PAY;
            case ONLINE_ALIPAY:
            case "alipay":
            case "alipay_pay":
            case "支付宝":
            case "cashier_alipay":
            case "cashier_alipay_enabled":
            case "cashieralipayenabled":
            case "cashier.alipay":
            case "cashier.channels.alipay":
            case "clients.cashier.channels.alipay":
            case "clients.cashier.effectivechannels.alipay":
            case NAME_ALIPAY_PAY:
                return NAME_ALIPAY_PAY;
            case ONLINE_BALANCE:
            case "balance":
            case "balance_pay":
            case "余额":
            case "cashier_balance":
            case "cashier_balance_enabled":
            case "cashierbalanceenabled":
            case "cashier.balance":
            case "cashier.channels.balance":
            case "clients.cashier.channels.balance":
            case "clients.cashier.effectivechannels.balance":
            case "mini_program_balance":
            case "mini_program_balance_enabled":
            case "miniprogrambalanceenabled":
            case "miniprogram.balance":
            case "clients.miniprogram.channels.balance":
            case NAME_BALANCE_PAY:
                return NAME_BALANCE_PAY;
            case ONLINE_COMBINED:
            case "combined":
            case "combination":
            case "combined_pay":
            case "cashier_combined":
            case "cashier_combined_enabled":
            case "cashiercombinedenabled":
            case "cashier.combined":
            case "cashier.channels.combined":
            case "clients.cashier.channels.combined":
            case "clients.cashier.effectivechannels.combined":
            case NAME_COMBINED_PAY:
                return NAME_COMBINED_PAY;
            case OFFLINE_WECHAT_QR:
            case "offline_wechat":
            case "wechat_qr":
            case "微信码":
            case "offline_collect_wechat":
            case "offlinecollect.wechat":
            case "channels.offlinecollect.wechat":
            case NAME_WECHAT_QR:
                return NAME_WECHAT_QR;
            case "offline_wechat_qr_auto":
            case "offline_wechat_auto":
            case "wechat_qr_auto":
            case "微信收款码(自动)":
            case "微信收款码（自动）":
            case "微信码自动":
            case NAME_WECHAT_QR_AUTO:
                return NAME_WECHAT_QR_AUTO;
            case OFFLINE_ALIPAY_QR:
            case "offline_alipay":
            case "alipay_qr":
            case "支付宝码":
            case "offline_collect_alipay":
            case "offlinecollect.alipay":
            case "channels.offlinecollect.alipay":
            case NAME_ALIPAY_QR:
                return NAME_ALIPAY_QR;
            case "offline_alipay_qr_auto":
            case "offline_alipay_auto":
            case "alipay_qr_auto":
            case "支付宝收款码(自动)":
            case "支付宝收款码（自动）":
            case "支付宝码自动":
            case NAME_ALIPAY_QR_AUTO:
                return NAME_ALIPAY_QR_AUTO;
            case RECEIVABLE:
            case "credit":
            case "on_account":
            case "onaccount":
            case NAME_RECEIVABLE:
                return NAME_RECEIVABLE;
            default:
                return trimmed;
        }
    }

    public static String codeFromPaymentMethod(String value) {
        String normalized = normalizePaymentMethod(value);
        if (NAME_WECHAT_PAY.equals(normalized)) {
            return ONLINE_WECHAT;
        }
        if (NAME_ALIPAY_PAY.equals(normalized)) {
            return ONLINE_ALIPAY;
        }
        if (NAME_BALANCE_PAY.equals(normalized)) {
            return ONLINE_BALANCE;
        }
        if (NAME_COMBINED_PAY.equals(normalized)) {
            return ONLINE_COMBINED;
        }
        if (NAME_WECHAT_QR.equals(normalized) || NAME_WECHAT_QR_AUTO.equals(normalized)) {
            return OFFLINE_WECHAT_QR;
        }
        if (NAME_ALIPAY_QR.equals(normalized) || NAME_ALIPAY_QR_AUTO.equals(normalized)) {
            return OFFLINE_ALIPAY_QR;
        }
        if (NAME_RECEIVABLE.equals(normalized)) {
            return RECEIVABLE;
        }
        if (NAME_CASH.equals(normalized)) {
            return CASH;
        }
        return null;
    }

    public static String typeFromPaymentMethod(String value) {
        String code = codeFromPaymentMethod(value);
        if (code == null) {
            return null;
        }
        return CASH.equals(code) || RECEIVABLE.equals(code) || code.startsWith("offline_") ? "offline" : "online";
    }

    /**
     * 财务报表渠道。收款方式中的收款码身份优先于历史账本的通用 WECHAT/ALIPAY 渠道，
     * 从而无需改写旧账本也能正确拆分；新账本的显式 *_QR 渠道可独立识别。
     */
    public static String reportingCode(String ledgerChannel, String paymentMethod) {
        String paymentCode = codeFromPaymentMethod(paymentMethod);
        if (OFFLINE_WECHAT_QR.equals(paymentCode)) {
            return REPORT_WECHAT_QR;
        }
        if (RECEIVABLE.equals(paymentCode)) {
            return RECEIVABLE;
        }
        if (OFFLINE_ALIPAY_QR.equals(paymentCode)) {
            return REPORT_ALIPAY_QR;
        }

        String raw = ledgerChannel == null ? "" : ledgerChannel.trim().toLowerCase(Locale.ROOT);
        if (raw.contains("wechat_qr") || raw.contains("wechat-qr") || raw.contains("微信收款码")) {
            return REPORT_WECHAT_QR;
        }
        if (raw.contains("alipay_qr") || raw.contains("alipay-qr") || raw.contains("支付宝收款码")) {
            return REPORT_ALIPAY_QR;
        }
        if (raw.contains("wechat") || raw.contains("wx") || raw.contains("微信")) {
            return REPORT_WECHAT;
        }
        if (raw.contains("alipay") || raw.contains("支付宝")) {
            return REPORT_ALIPAY;
        }
        if (raw.contains("cash") || raw.contains("现金")) {
            return CASH;
        }
        if (raw.contains("balance") || raw.contains("member") || raw.contains("余额")) {
            return "balance";
        }
        if (raw.contains("receivable") || raw.contains("credit") || raw.contains("挂账")) {
            return RECEIVABLE;
        }
        if (raw.contains("gift") || raw.contains("赠送")) {
            return "gift";
        }

        if (ONLINE_WECHAT.equals(paymentCode)) return REPORT_WECHAT;
        if (ONLINE_ALIPAY.equals(paymentCode)) return REPORT_ALIPAY;
        if (CASH.equals(paymentCode)) return CASH;
        if (ONLINE_BALANCE.equals(paymentCode)) return "balance";
        return raw.isEmpty() ? "other" : raw;
    }

    public static String reportingLabel(String reportingCode) {
        if (REPORT_WECHAT_QR.equals(reportingCode)) return NAME_WECHAT_QR;
        if (REPORT_ALIPAY_QR.equals(reportingCode)) return NAME_ALIPAY_QR;
        if (REPORT_WECHAT.equals(reportingCode)) return NAME_WECHAT_PAY;
        if (REPORT_ALIPAY.equals(reportingCode)) return "支付宝";
        if (CASH.equals(reportingCode)) return NAME_CASH;
        if ("balance".equals(reportingCode)) return "会员余额";
        if (RECEIVABLE.equals(reportingCode) || "挂账".equals(reportingCode)) return NAME_RECEIVABLE;
        if ("gift".equals(reportingCode)) return "赠送金";
        return reportingCode;
    }

    /** 新结算账本仅在收款方式明确为收款码时升级为独立渠道。 */
    public static String ledgerChannel(String paymentMethod, String fallbackChannel) {
        String paymentCode = codeFromPaymentMethod(paymentMethod);
        if (OFFLINE_WECHAT_QR.equals(paymentCode)
                && (fallbackChannel == null || "WECHAT".equalsIgnoreCase(fallbackChannel)
                || "WECHAT_QR".equalsIgnoreCase(fallbackChannel))) {
            return "WECHAT_QR";
        }
        if (OFFLINE_ALIPAY_QR.equals(paymentCode)
                && (fallbackChannel == null || "ALIPAY".equalsIgnoreCase(fallbackChannel)
                || "ALIPAY_QR".equalsIgnoreCase(fallbackChannel))) {
            return "ALIPAY_QR";
        }
        return fallbackChannel;
    }

    public static Map<String, Object> groupedMethods(boolean wechatEnabled,
                                                     boolean alipayEnabled,
                                                     boolean balanceEnabled,
                                                     boolean combinedEnabled,
                                                     boolean offlineWechatEnabled,
                                                     boolean offlineAlipayEnabled) {
        Map<String, Object> groups = new LinkedHashMap<>();
        List<Map<String, Object>> online = new ArrayList<>();
        online.add(method(ONLINE_WECHAT, NAME_WECHAT_PAY, "online", wechatEnabled));
        online.add(method(ONLINE_ALIPAY, NAME_ALIPAY_PAY, "online", alipayEnabled));
        online.add(method(ONLINE_BALANCE, NAME_BALANCE_PAY, "online", balanceEnabled));
        online.add(method(ONLINE_COMBINED, NAME_COMBINED_PAY, "online", combinedEnabled));
        List<Map<String, Object>> offline = new ArrayList<>();
        offline.add(method(OFFLINE_WECHAT_QR, NAME_WECHAT_QR, "offline", offlineWechatEnabled));
        offline.add(method(OFFLINE_ALIPAY_QR, NAME_ALIPAY_QR, "offline", offlineAlipayEnabled));
        groups.put("online", online);
        groups.put("offline", offline);
        return groups;
    }

    public static List<Map<String, Object>> cashierMethods(boolean cashEnabled,
                                                           boolean offlineWechatEnabled,
                                                           boolean offlineAlipayEnabled,
                                                           boolean balanceEnabled,
                                                           boolean combinedEnabled) {
        List<Map<String, Object>> methods = new ArrayList<>();
        methods.add(method(CASH, NAME_CASH, "offline", cashEnabled));
        methods.add(method(OFFLINE_WECHAT_QR, NAME_WECHAT_QR, "offline", offlineWechatEnabled));
        methods.add(method(OFFLINE_ALIPAY_QR, NAME_ALIPAY_QR, "offline", offlineAlipayEnabled));
        methods.add(method(ONLINE_BALANCE, NAME_BALANCE_PAY, "online", balanceEnabled));
        methods.add(method(ONLINE_COMBINED, NAME_COMBINED_PAY, "online", combinedEnabled));
        return methods;
    }

    public static List<Map<String, Object>> miniProgramMethods(boolean wechatEnabled,
                                                               boolean balanceEnabled) {
        List<Map<String, Object>> methods = new ArrayList<>();
        methods.add(method(ONLINE_WECHAT, NAME_WECHAT_PAY, "online", wechatEnabled));
        methods.add(method(ONLINE_BALANCE, NAME_BALANCE_PAY, "online", balanceEnabled));
        return methods;
    }

    private static Map<String, Object> method(String code, String name, String type, boolean enabled) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("code", code);
        out.put("name", name);
        out.put("type", type);
        out.put("enabled", enabled);
        return out;
    }
}
