package com.lanf.kds.support;

/** Marks cloud order creation that originated from the cashier outbox. */
public final class KdsCloudReplicationContext {

    private static final ThreadLocal<Boolean> ACTIVE = new ThreadLocal<>();

    private KdsCloudReplicationContext() {
    }

    public static boolean isActive() {
        return Boolean.TRUE.equals(ACTIVE.get());
    }

    public static Scope open() {
        ACTIVE.set(Boolean.TRUE);
        return new Scope();
    }

    public static final class Scope implements AutoCloseable {
        private boolean closed;

        private Scope() {
        }

        @Override
        public void close() {
            if (!closed) {
                ACTIVE.remove();
                closed = true;
            }
        }
    }
}
