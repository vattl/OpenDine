package com.lanf.kds.event;

import org.springframework.context.ApplicationEvent;

/**
 * KDS 整单状态已变化（10/20/30/40/90）。
 * 由 {@code KdsOrderStatusAggregator} 在算出新状态且与旧值不同后发布，
 * 监听器在事务提交后广播 WS {@code order_status_changed}。
 */
public class KdsOrderStatusChangedEvent extends ApplicationEvent {

    private final int shopId;
    private final int orderId;
    private final String orderNo;
    private final int fromStatus;
    private final int toStatus;

    public KdsOrderStatusChangedEvent(Object source, int shopId, int orderId, String orderNo,
                                      int fromStatus, int toStatus) {
        super(source);
        this.shopId = shopId;
        this.orderId = orderId;
        this.orderNo = orderNo;
        this.fromStatus = fromStatus;
        this.toStatus = toStatus;
    }

    public int getShopId() {
        return shopId;
    }

    public int getOrderId() {
        return orderId;
    }

    public String getOrderNo() {
        return orderNo;
    }

    public int getFromStatus() {
        return fromStatus;
    }

    public int getToStatus() {
        return toStatus;
    }
}
