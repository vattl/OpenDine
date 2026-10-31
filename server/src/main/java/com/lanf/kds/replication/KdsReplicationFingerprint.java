package com.lanf.kds.replication;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;

/** Canonical semantic request fingerprint; idempotency identifiers themselves are intentionally excluded. */
public final class KdsReplicationFingerprint {
    private KdsReplicationFingerprint() {
    }

    public static String compute(ObjectMapper mapper, int shopId, String eventType, String aggregateKey,
                                 long occurredAtMs, String publisherDeviceCode, JsonNode payload) {
        try {
            ObjectNode request = mapper.createObjectNode();
            request.put("shop_id", shopId);
            request.put("event_type", eventType);
            request.put("aggregate_key", aggregateKey);
            request.put("occurred_at_ms", occurredAtMs);
            request.put("publisher_device_code", publisherDeviceCode);
            request.set("payload", canonical(mapper, payload));
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(mapper.writeValueAsBytes(canonical(mapper, request)));
            StringBuilder hex = new StringBuilder(64);
            for (byte value : digest) hex.append(String.format("%02x", value));
            return hex.toString();
        } catch (Exception ex) {
            throw new IllegalStateException("replication request fingerprint calculation failed", ex);
        }
    }

    private static JsonNode canonical(ObjectMapper mapper, JsonNode value) {
        if (value == null || value.isNull() || value.isValueNode()) return value;
        if (value.isArray()) {
            ArrayNode result = mapper.createArrayNode();
            for (JsonNode item : value) result.add(canonical(mapper, item));
            return result;
        }
        ObjectNode result = mapper.createObjectNode();
        List<String> fields = new ArrayList<>();
        Iterator<String> iterator = value.fieldNames();
        while (iterator.hasNext()) fields.add(iterator.next());
        Collections.sort(fields);
        for (String field : fields) result.set(field, canonical(mapper, value.get(field)));
        return result;
    }
}
