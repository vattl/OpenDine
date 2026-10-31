package com.lanf.integration.exception;

import com.lanf.integration.remote.dto.ZsqCreateOrderResult;

/**
 * 真省钱 open 订单已创建，但询价/发配送失败（如余额不足）。
 * 调用方应落库 {@link #getCreatedOrder()} 后，充值后可对同一 openOrderId 仅重试发配送。
 */
public class ZsqPartialDispatchException extends ZsqApiException {

    private final ZsqCreateOrderResult createdOrder;

    public ZsqPartialDispatchException(ZsqCreateOrderResult createdOrder, ZsqApiException cause) {
        super(cause.getCode(), cause.getMessage(), cause.getTraceId());
        this.createdOrder = createdOrder;
        initCause(cause);
    }

    public ZsqPartialDispatchException(ZsqCreateOrderResult createdOrder, String message) {
        super(message);
        this.createdOrder = createdOrder;
    }

    public ZsqCreateOrderResult getCreatedOrder() {
        return createdOrder;
    }
}
