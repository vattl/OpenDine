package com.lanf.common;

/**
 * 业务 API 异常：携带真实 HTTP 状态码与稳定错误码（见系统设置协调文档 §1/§4）。
 * 由 GlobalApiExceptionHandler 统一转换为
 * HTTP {httpStatus} + body {code, error, msg, data}。
 */
public class ApiException extends RuntimeException {

    private final int httpStatus;
    private final String errorCode;
    private final Object data;

    public ApiException(int httpStatus, String errorCode, String msg) {
        this(httpStatus, errorCode, msg, null);
    }

    public ApiException(int httpStatus, String errorCode, String msg, Object data) {
        super(msg);
        this.httpStatus = httpStatus;
        this.errorCode = errorCode;
        this.data = data;
    }

    public int getHttpStatus() {
        return httpStatus;
    }

    public String getErrorCode() {
        return errorCode;
    }

    public Object getData() {
        return data;
    }
}
