package com.lanf.kds.service;

import java.util.LinkedHashMap;
import java.util.Map;

/** A previously persisted, deterministic business rejection for a KDS command. */
public final class KdsV2RejectedCommandException extends RuntimeException {

    private final int httpStatus;
    private final int businessCode;
    private final Map<String, Object> result;

    public KdsV2RejectedCommandException(int httpStatus, int businessCode,
                                         String message, Map<String, Object> result) {
        super(message);
        this.httpStatus = httpStatus;
        this.businessCode = businessCode;
        this.result = new LinkedHashMap<>(result);
    }

    public int getHttpStatus() {
        return httpStatus;
    }

    public int getBusinessCode() {
        return businessCode;
    }

    public Map<String, Object> getResult() {
        return new LinkedHashMap<>(result);
    }
}
