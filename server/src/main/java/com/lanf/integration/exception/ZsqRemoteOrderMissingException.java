package com.lanf.integration.exception;

/** 真省钱侧配送订单已不存在，本地配送可重新创建并发单。 */
public class ZsqRemoteOrderMissingException extends IllegalStateException {

    public static final String USER_MESSAGE = "真省钱配送订单不存在或已删除，可重新下单配送";

    private final Long missingOpenOrderId;

    public ZsqRemoteOrderMissingException(Long missingOpenOrderId, Throwable cause) {
        super(USER_MESSAGE, cause);
        this.missingOpenOrderId = missingOpenOrderId;
    }

    public Long getMissingOpenOrderId() {
        return missingOpenOrderId;
    }
}
