package com.lanf.util;

import com.lanf.entity.TakeoutDelivery;
import org.springframework.util.StringUtils;

/**
 * 真省钱配送取消/重发后本地 {@code t_takeout_delivery} 状态恢复。
 */
public final class TakeoutZsqDispatchRecovery {

    private TakeoutZsqDispatchRecovery() {
    }

    /**
     * 运营重发前：解除本地终态并清空上一轮配送尝试；远端 open 订单仍存在时保留并复用。
     */
    public static void prepareLocalForRedispatch(TakeoutDelivery delivery) {
        if (delivery == null) {
            return;
        }
        String zsqSt = normalize(delivery.getZsq_dispatch_status());
        String ds = normalize(delivery.getDispatch_status());
        boolean locallyCancelled = "cancelled".equals(zsqSt) || "cancelled".equals(ds);
        boolean remoteOrderMissing = "order_missing".equals(zsqSt);
        boolean completed = "completed".equals(zsqSt) || "completed".equals(ds);
        boolean redispatchable = locallyCancelled
                || remoteOrderMissing
                || completed
                || "failed".equals(zsqSt)
                || "rider_cancelled".equals(zsqSt)
                || "dispatch_failed".equals(ds);
        if (!redispatchable) {
            return;
        }
        if (remoteOrderMissing) {
            delivery.setZsq_open_order_id(null);
            delivery.setZsq_order_id(null);
            delivery.setZsq_shop_number(null);
        }
        delivery.setZsq_parent_order_no(null);
        delivery.setZsq_cancel_prompt(null);
        delivery.setZsq_cancel_json(null);
        delivery.setZsq_liability_fee(null);
        delivery.setZsq_actual_fee(null);
        delivery.setZsq_delivery_supplier_name(null);
        delivery.setZsq_phase(null);
        delivery.setZsq_dispatch_status("none");
        delivery.setZsq_delivery_codes_json(null);
        delivery.setZsq_quote_json(null);
        delivery.setZsq_dispatch_json(null);
        clearOperatorCancelRemark(delivery);
        clearStaleTrackingForNewDispatch(delivery);
        if ("cancelled".equals(ds) || "dispatch_failed".equals(ds) || completed) {
            delivery.setDispatch_status("accepted");
        }
        delivery.setZsq_last_error(null);
    }

    private static void clearOperatorCancelRemark(TakeoutDelivery delivery) {
        String remark = delivery.getMerchant_remark();
        if (!StringUtils.hasText(remark) || !remark.contains("ZSQ取消:")) {
            return;
        }
        StringBuilder retained = new StringBuilder();
        for (String part : remark.split(";")) {
            String value = part.trim();
            if (!StringUtils.hasText(value) || value.startsWith("ZSQ取消:")) {
                continue;
            }
            if (retained.length() > 0) {
                retained.append(';');
            }
            retained.append(value);
        }
        delivery.setMerchant_remark(retained.length() > 0 ? retained.toString() : null);
    }

    /** 新一轮配送开始前清除上一配送单的状态、骑手和定位，避免前端展示历史轨迹。 */
    public static void clearStaleTrackingForNewDispatch(TakeoutDelivery delivery) {
        if (delivery == null) {
            return;
        }
        delivery.setZsq_phase(null);
        delivery.setZsq_delivery_send_status(null);
        delivery.setZsq_rider_name(null);
        delivery.setZsq_rider_phone(null);
        delivery.setZsq_rider_lat(null);
        delivery.setZsq_rider_lng(null);
        delivery.setZsq_rider_updated_at(null);
        delivery.setZsq_actual_fee(null);
        delivery.setZsq_delivery_supplier_name(null);
    }

    /**
     * 本地仍为 cancelled，但真省钱追踪已进入非取消阶段 → 应解除取消锁并同步履约状态。
     * 运营/用户主动取消（见 {@link #hasOperatorCancelLock}）时不恢复，避免前端仍显示「发单中」。
     */
    public static boolean shouldRecoverFromActiveZsqPhase(TakeoutDelivery delivery, String zsqPhase) {
        if (delivery == null || !StringUtils.hasText(zsqPhase)) {
            return false;
        }
        if ("CANCELLED".equals(zsqPhase.trim())) {
            return false;
        }
        if (hasOperatorCancelLock(delivery)) {
            return false;
        }
        return "cancelled".equals(normalize(delivery.getDispatch_status()))
                || "cancelled".equals(normalize(delivery.getZsq_dispatch_status()));
    }

    /** 本系统已发起真省钱取消（含运营取消配送），不应被定时同步「恢复」为待发单。 */
    public static boolean hasOperatorCancelLock(TakeoutDelivery delivery) {
        if (delivery == null) {
            return false;
        }
        String remark = delivery.getMerchant_remark();
        if (StringUtils.hasText(remark) && remark.contains("ZSQ取消:")) {
            return true;
        }
        if (StringUtils.hasText(delivery.getZsq_cancel_prompt())) {
            return true;
        }
        String cancelJson = delivery.getZsq_cancel_json();
        return StringUtils.hasText(cancelJson) && !"null".equalsIgnoreCase(cancelJson.trim());
    }

    public static void applyRecoveryFromActiveZsqPhase(TakeoutDelivery delivery) {
        if (delivery == null) {
            return;
        }
        if ("cancelled".equals(normalize(delivery.getDispatch_status()))) {
            delivery.setDispatch_status("accepted");
        }
        if ("cancelled".equals(normalize(delivery.getZsq_dispatch_status()))) {
            delivery.setZsq_dispatch_status("pending");
        }
        delivery.setZsq_last_error(null);
    }

    /** 运营/用户取消后本地终态（与 OpenAPI v1.2.57 一致）。 */
    public static void finalizeOperatorCancel(TakeoutDelivery delivery) {
        if (delivery == null) {
            return;
        }
        delivery.setDispatch_status("cancelled");
        delivery.setZsq_dispatch_status("cancelled");
        delivery.setZsq_phase("CANCELLED");
        delivery.setZsq_last_error(null);
    }

    public static void appendCancelRemark(TakeoutDelivery delivery, String reason) {
        if (delivery == null || !StringUtils.hasText(reason)) {
            return;
        }
        String remark = delivery.getMerchant_remark();
        if (remark != null && remark.contains("ZSQ取消:")) {
            return;
        }
        delivery.setMerchant_remark((remark != null ? remark + ";" : "") + "ZSQ取消:" + reason.trim());
    }

    static String normalize(String status) {
        return status == null || status.trim().isEmpty() ? "none" : status.trim().toLowerCase();
    }
}
