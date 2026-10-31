package com.lanf.event;

/**
 * 外卖订单商家已接单（自动或手动）；若门店开启 {@code zsq.auto_api.enabled} 则尝试自动发真省钱配送。
 */
public class TakeoutOrderAcceptedEvent {

    private final Integer orderId;

    public TakeoutOrderAcceptedEvent(Integer orderId) {
        this.orderId = orderId;
    }

    public Integer getOrderId() {
        return orderId;
    }
}
