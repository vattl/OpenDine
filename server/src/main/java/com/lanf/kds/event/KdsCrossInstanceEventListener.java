package com.lanf.kds.event;

@FunctionalInterface
public interface KdsCrossInstanceEventListener {
    void onEvent(KdsCrossInstanceEventMessage message);
}
