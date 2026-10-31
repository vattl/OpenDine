package com.lanf.kds.event;

/** Signals that every live WebSocket authenticated by the previous credential must close. */
public final class KdsDeviceCredentialChangedEvent {
    private final int shopId;
    private final String deviceCode;

    public KdsDeviceCredentialChangedEvent(int shopId, String deviceCode) {
        this.shopId = shopId;
        this.deviceCode = deviceCode;
    }

    public int getShopId() {
        return shopId;
    }

    public String getDeviceCode() {
        return deviceCode;
    }
}
