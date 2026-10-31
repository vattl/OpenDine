package com.lanf.integration.exception;

public class ZsqApiException extends RuntimeException {

    private final int code;
    private final String traceId;

    public ZsqApiException(String message) {
        super(message);
        this.code = -1;
        this.traceId = null;
    }

    public ZsqApiException(int code, String message, String traceId) {
        super(message);
        this.code = code;
        this.traceId = traceId;
    }

    public int getCode() {
        return code;
    }

    public String getTraceId() {
        return traceId;
    }
}
