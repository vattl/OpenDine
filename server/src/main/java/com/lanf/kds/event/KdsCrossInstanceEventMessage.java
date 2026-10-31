package com.lanf.kds.event;

import java.io.Serializable;

/**
 * DTO for broadcasting KDS V2 events across multiple backend instances.
 */
public class KdsCrossInstanceEventMessage implements Serializable {
    private static final long serialVersionUID = 1L;

    private String originInstanceId;
    private int shopId;
    private Long eventSeq;
    private String eventId;
    private String envelopeJson;
    private long timestampMs;

    public KdsCrossInstanceEventMessage() {}

    public KdsCrossInstanceEventMessage(String originInstanceId, int shopId, Long eventSeq, String eventId, String envelopeJson, long timestampMs) {
        this.originInstanceId = originInstanceId;
        this.shopId = shopId;
        this.eventSeq = eventSeq;
        this.eventId = eventId;
        this.envelopeJson = envelopeJson;
        this.timestampMs = timestampMs;
    }

    public String getOriginInstanceId() {
        return originInstanceId;
    }

    public void setOriginInstanceId(String originInstanceId) {
        this.originInstanceId = originInstanceId;
    }

    public int getShopId() {
        return shopId;
    }

    public void setShopId(int shopId) {
        this.shopId = shopId;
    }

    public Long getEventSeq() {
        return eventSeq;
    }

    public void setEventSeq(Long eventSeq) {
        this.eventSeq = eventSeq;
    }

    public String getEventId() {
        return eventId;
    }

    public void setEventId(String eventId) {
        this.eventId = eventId;
    }

    public String getEnvelopeJson() {
        return envelopeJson;
    }

    public void setEnvelopeJson(String envelopeJson) {
        this.envelopeJson = envelopeJson;
    }

    public long getTimestampMs() {
        return timestampMs;
    }

    public void setTimestampMs(long timestampMs) {
        this.timestampMs = timestampMs;
    }
}
