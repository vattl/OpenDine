package com.lanf.kds;

public final class KdsItemStatus {

    public static final int PENDING = 0;
    public static final int COOKING = 1;
    public static final int DONE = 2;
    public static final int VOID = 3;

    private KdsItemStatus() {
    }

    public static boolean isValid(int status) {
        return status >= PENDING && status <= VOID;
    }
}
