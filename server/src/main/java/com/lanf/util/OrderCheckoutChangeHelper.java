package com.lanf.util;

import com.lanf.entity.Order;

import java.util.Collections;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * 后台/收银结账找零：客人付现大于账单现金部分时记录找零金额与找零渠道。
 */
public final class OrderCheckoutChangeHelper {

    private static final double EPS = 0.02d;

    public static final Set<String> SUPPORTED_CHANGE_CHANNELS = Collections.unmodifiableSet(
            new HashSet<>(java.util.Arrays.asList("wechat", "cash", "alipay")));

    private OrderCheckoutChangeHelper() {
    }

    public static final class ResolvedChange {
        public Double cashTenderYuan;
        public double changeAmountYuan;
        public String changeChannel;

        public ResolvedChange() {
        }
    }

  /**
   * @param cashAppliedToBillYuan 本单计入 {@code pay_amount_cash} 的现金实收（元）
   */
    public static String validateAndResolve(Order request, double cashAppliedToBillYuan, ResolvedChange out) {
        if (request == null) {
            out.changeAmountYuan = 0d;
            out.changeChannel = null;
            out.cashTenderYuan = null;
            return null;
        }
        Double tender = firstNonNull(
                request.getCheckout_cash_tender(),
                request.getCashTender());
        Double explicitChange = firstNonNull(
                request.getCheckout_change_amount(),
                request.getChangeAmount());
        String channelRaw = firstNonBlank(
                request.getCheckout_change_channel(),
                request.getChangeChannel());

        if (tender != null && (Double.isNaN(tender) || tender < 0d)) {
            return "客人付现金额无效";
        }
        if (explicitChange != null && (Double.isNaN(explicitChange) || explicitChange < 0d)) {
            return "找零金额无效";
        }

        double cashBill = cashAppliedToBillYuan > 0d && !Double.isNaN(cashAppliedToBillYuan)
                ? Math.round(cashAppliedToBillYuan * 100) / 100.0 : 0d;

        double change;
        if (tender != null && tender > 0d) {
            if (cashBill <= 0d) {
                return "未含现金实收时不可登记付现找零";
            }
            if (tender + EPS < cashBill) {
                return "客人付现金额不能小于现金实收";
            }
            change = Math.round((tender - cashBill) * 100) / 100.0;
            if (explicitChange != null && Math.abs(explicitChange - change) > EPS) {
                return "找零金额与付现金额不一致";
            }
            out.cashTenderYuan = Math.round(tender * 100) / 100.0;
        } else if (explicitChange != null && explicitChange > EPS) {
            if (cashBill <= 0d) {
                return "未含现金实收时不可登记找零";
            }
            change = Math.round(explicitChange * 100) / 100.0;
            out.cashTenderYuan = Math.round((cashBill + change) * 100) / 100.0;
        } else {
            out.cashTenderYuan = null;
            out.changeAmountYuan = 0d;
            out.changeChannel = null;
            return null;
        }

        if (change <= EPS) {
            out.cashTenderYuan = tender != null ? Math.round(tender * 100) / 100.0 : null;
            out.changeAmountYuan = 0d;
            out.changeChannel = null;
            return null;
        }

        String channel = normalizeChangeChannel(channelRaw);
        if (channel == null) {
            return "找零金额大于0时须指定找零渠道（wechat/cash/alipay）";
        }
        out.changeAmountYuan = change;
        out.changeChannel = channel;
        return null;
    }

    public static void applyToOrder(Order order, ResolvedChange resolved) {
        if (order == null || resolved == null) {
            return;
        }
        order.setCheckout_cash_tender(resolved.cashTenderYuan);
        order.setCheckout_change_amount(resolved.changeAmountYuan > 0d ? resolved.changeAmountYuan : 0d);
        order.setCheckout_change_channel(resolved.changeAmountYuan > 0d ? resolved.changeChannel : null);
        enrichOrderChangeDisplay(order);
    }

    /** 详情/列表返回前填充找零展示字段（不落库） */
    public static void enrichOrderChangeDisplay(Order order) {
        if (order == null) {
            return;
        }
        Double changeAmt = order.getCheckout_change_amount();
        String channel = order.getCheckout_change_channel();
        if (changeAmt != null && changeAmt > 0d && channel != null && !channel.trim().isEmpty()) {
            order.setCheckout_change_channel_label(changeChannelLabel(channel));
        } else {
            order.setCheckout_change_channel_label(null);
        }
    }

    public static void clear(Order order) {
        if (order == null) {
            return;
        }
        order.setCheckout_cash_tender(null);
        order.setCheckout_change_amount(0d);
        order.setCheckout_change_channel(null);
        order.setCheckout_change_channel_label(null);
    }

    /** 从 Map 请求体填充 Order 上的找零字段（收银端等） */
    public static void fillFromMap(Order order, Map<String, Object> body) {
        if (order == null || body == null || body.isEmpty()) {
            return;
        }
        order.setCheckout_cash_tender(asDouble(first(body,
                "checkout_cash_tender", "cash_tender", "cashTender", "tender_amount", "tenderAmount")));
        order.setCheckout_change_amount(asDouble(first(body,
                "checkout_change_amount", "change_amount", "changeAmount")));
        order.setCheckout_change_channel(asText(first(body,
                "checkout_change_channel", "change_channel", "changeChannel")));
        order.setCashTender(order.getCheckout_cash_tender());
        order.setChangeAmount(order.getCheckout_change_amount());
        order.setChangeChannel(order.getCheckout_change_channel());
    }

    public static String normalizeChangeChannel(String raw) {
        if (raw == null || raw.trim().isEmpty()) {
            return null;
        }
        String s = raw.trim().toLowerCase(Locale.ROOT);
        if ("微信".equals(raw.trim()) || "微信支付".equals(raw.trim())) {
            return "wechat";
        }
        if ("现金".equals(raw.trim())) {
            return "cash";
        }
        if ("支付宝".equals(raw.trim()) || "alipay".equalsIgnoreCase(raw.trim())) {
            return "alipay";
        }
        if (SUPPORTED_CHANGE_CHANNELS.contains(s)) {
            return s;
        }
        return null;
    }

    public static String changeChannelLabel(String code) {
        if (code == null) {
            return "";
        }
        switch (code.trim().toLowerCase(Locale.ROOT)) {
            case "wechat":
                return "微信";
            case "cash":
                return "现金";
            case "alipay":
                return "支付宝";
            default:
                return code;
        }
    }

    private static Double firstNonNull(Double a, Double b) {
        return a != null ? a : b;
    }

    private static String firstNonBlank(String a, String b) {
        if (a != null && !a.trim().isEmpty()) {
            return a.trim();
        }
        if (b != null && !b.trim().isEmpty()) {
            return b.trim();
        }
        return null;
    }

    private static Object first(Map<String, Object> map, String... keys) {
        for (String k : keys) {
            if (map.containsKey(k) && map.get(k) != null) {
                return map.get(k);
            }
        }
        return null;
    }

    private static Double asDouble(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Number) {
            return ((Number) o).doubleValue();
        }
        try {
            return Double.parseDouble(o.toString().trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String asText(Object o) {
        return o == null ? null : o.toString().trim();
    }
}
