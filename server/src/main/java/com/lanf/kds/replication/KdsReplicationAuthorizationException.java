package com.lanf.kds.replication;

/** Permanent publisher-identity rejection; the stored inbox event must not be mutated. */
public class KdsReplicationAuthorizationException extends RuntimeException {
    public KdsReplicationAuthorizationException(String message) {
        super(message);
    }
}
