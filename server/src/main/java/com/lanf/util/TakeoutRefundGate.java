package com.lanf.util;

import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;
import org.springframework.util.StringUtils;

/**
 * 外卖订单退款前置校验：已发配送须履约 completed 后才可退；退款流程不取消真省钱单。
 */
public final class TakeoutRefundGate {

    private TakeoutRefundGate() {
    }

    /**
     * @return null 表示允许退款，否则为应返回给前端的错误说明
     */
    public static String blockReason(Order order, TakeoutDelivery delivery) {
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            return null;
        }
        if (delivery == null) {
            return "外卖订单缺少配送记录，无法退款";
        }
        if (hasDeliveryStarted(delivery) && !"completed".equals(normalizeStatus(delivery.getDispatch_status()))) {
            String status = delivery.getDispatch_status() != null ? delivery.getDispatch_status() : "未知";
            return "外卖订单已发配送，须配送完成后方可退款（当前履约状态：" + status + "）";
        }
        return null;
    }

    /** 是否已发生配送（已关联真省钱或处于配送中/终态履约）。 */
    public static boolean hasDeliveryStarted(TakeoutDelivery delivery) {
        if (delivery == null) {
            return false;
        }
        if (delivery.getZsq_open_order_id() != null) {
            return true;
        }
        String ds = normalizeStatus(delivery.getDispatch_status());
        if ("delivering".equals(ds) || "completed".equals(ds) || "dispatch_failed".equals(ds)) {
            return true;
        }
        String zsq = normalizeStatus(delivery.getZsq_dispatch_status());
        return "pending".equals(zsq) || "dispatched".equals(zsq) || "rider_cancelled".equals(zsq)
                || "completed".equals(zsq);
    }

    private static String normalizeStatus(String status) {
        return StringUtils.hasText(status) ? status.trim().toLowerCase() : "";
    }
}
