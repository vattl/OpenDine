package com.lanf.kds.replication;

import lombok.AllArgsConstructor;
import lombok.Getter;

import java.util.Map;

@Getter
@AllArgsConstructor
public class KdsReplicationOutcome {
    private final int httpStatus;
    private final int businessCode;
    private final String message;
    private final Map<String, Object> data;

    public static KdsReplicationOutcome ok(Map<String, Object> data) {
        return new KdsReplicationOutcome(200, 0, "accepted", data);
    }

    public static KdsReplicationOutcome invalid(String message) {
        return new KdsReplicationOutcome(400, 4000, message, null);
    }

    public static KdsReplicationOutcome forbidden(String message) {
        return new KdsReplicationOutcome(403, 4030, message, null);
    }

    public static KdsReplicationOutcome pending(String message, Map<String, Object> data) {
        return new KdsReplicationOutcome(409, 4090, message, data);
    }

    public static KdsReplicationOutcome conflict(String message, Map<String, Object> data) {
        return new KdsReplicationOutcome(409, 4091, message, data);
    }

    public static KdsReplicationOutcome blocked(String eventId, String aggregateKey) {
        java.util.LinkedHashMap<String, Object> data = new java.util.LinkedHashMap<>();
        data.put("event_id", eventId);
        data.put("aggregate_key", aggregateKey);
        data.put("accepted", false);
        data.put("blocked", true);
        return new KdsReplicationOutcome(409, 4092,
                "blocked by an earlier non-success result for this aggregate", data);
    }

    public static KdsReplicationOutcome failure(String message) {
        return new KdsReplicationOutcome(500, 5000, message, null);
    }
}
