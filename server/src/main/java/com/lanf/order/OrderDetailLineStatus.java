package com.lanf.order;

/**
 * 订单明细行状态（t_order_detail.line_status）。
 */
public final class OrderDetailLineStatus {

    public static final String NORMAL = "normal";
    /** 已退菜：不参与计价与 KDS 新工单，库存已回退 */
    public static final String REFUNDED = "refunded";

    private OrderDetailLineStatus() {
    }

    public static boolean isActive(String lineStatus) {
        return lineStatus == null || lineStatus.trim().isEmpty()
                || NORMAL.equalsIgnoreCase(lineStatus.trim());
    }

    public static boolean isRefunded(String lineStatus) {
        return REFUNDED.equalsIgnoreCase(lineStatus != null ? lineStatus.trim() : "");
    }
}
