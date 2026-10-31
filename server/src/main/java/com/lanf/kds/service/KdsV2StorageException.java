package com.lanf.kds.service;

/** Signals a KDS V2 durable-state invariant or serialization failure. */
public class KdsV2StorageException extends RuntimeException {

    public KdsV2StorageException(String message) {
        super(message);
    }

    public KdsV2StorageException(String message, Throwable cause) {
        super(message, cause);
    }
}
