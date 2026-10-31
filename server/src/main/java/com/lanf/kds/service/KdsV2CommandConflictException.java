package com.lanf.kds.service;

/** The same shop-scoped command id was reused for different command data. */
public final class KdsV2CommandConflictException extends RuntimeException {

    public KdsV2CommandConflictException(String message) {
        super(message);
    }
}
