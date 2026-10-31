package com.lanf.util;

import com.lanf.entity.Order;

/**
 * 订单营业额/净收入口径（与统计 SQL 一致）：
 * {@code sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift}（元，保留两位小数）。
 * <p>
 * {@link #storeLineBeforeRefundYuan(Order)} 不含 {@code refund_amount}，用于「原价款 − 赠送金支付」封顶后再单独扣退款（如邀请返现冲正）。
 */
public final class OrderNetRevenue {

    private OrderNetRevenue() {
    }

    /** 净营业额（元）：含已退金额扣减、扣除赠送金账户支付部分 */
    public static double netRevenueYuan(Order o) {
        if (o == null) {
            return 0d;
        }
        double sett = o.getSett_amount() != null ? o.getSett_amount() : 0d;
        double disc = o.getDiscount_amount() != null ? o.getDiscount_amount() : 0d;
        double svc = o.getService_fee() != null ? o.getService_fee() : 0d;
        double ref = o.getRefund_amount() != null ? o.getRefund_amount() : 0d;
        double gift = o.getPay_amount_gift() != null ? o.getPay_amount_gift() : 0d;
        return Math.round((sett - disc + svc - ref - gift) * 100d) / 100d;
    }

    /** 净营业额（分） */
    public static int netRevenueFen(Order o) {
        return (int) Math.round(netRevenueYuan(o) * 100d);
    }

    /** 门店计量流水（元）：不减退款，用于与 {@code refund_amount} 组合算剩余 */
    public static double storeLineBeforeRefundYuan(Order o) {
        if (o == null) {
            return 0d;
        }
        double sett = o.getSett_amount() != null ? o.getSett_amount() : 0d;
        double disc = o.getDiscount_amount() != null ? o.getDiscount_amount() : 0d;
        double svc = o.getService_fee() != null ? o.getService_fee() : 0d;
        double gift = o.getPay_amount_gift() != null ? o.getPay_amount_gift() : 0d;
        return Math.round((sett - disc + svc - gift) * 100d) / 100d;
    }
}
