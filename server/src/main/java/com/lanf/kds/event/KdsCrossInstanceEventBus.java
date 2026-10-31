package com.lanf.kds.event;

import java.util.Map;

/**
 * Cross-instance event bus interface for KDS realtime events.
 */
public interface KdsCrossInstanceEventBus {
    String getInstanceId();
    void publish(int shopId, Map<String, Object> envelope);
    void registerListener(KdsCrossInstanceEventListener listener);
}
