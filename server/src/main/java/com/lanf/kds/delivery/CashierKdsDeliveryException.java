package com.lanf.kds.delivery;

public class CashierKdsDeliveryException extends RuntimeException {
    private final int httpStatus;
    private final int code;

    public CashierKdsDeliveryException(int httpStatus, int code, String message) {
        super(message);
        this.httpStatus = httpStatus;
        this.code = code;
    }

    public int getHttpStatus() { return httpStatus; }
    public int getCode() { return code; }
}
