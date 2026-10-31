package com.lanf.kds.replication;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

class KdsReplicationFingerprintTest {
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void objectFieldOrderDoesNotChangeCanonicalFingerprint() throws Exception {
        JsonNode first = mapper.readTree("{\"local_order_id\":37,\"nested\":{\"b\":2,\"a\":1}}");
        JsonNode reordered = mapper.readTree("{\"nested\":{\"a\":1,\"b\":2},\"local_order_id\":37}");

        assertEquals(fingerprint(7, first), fingerprint(7, reordered));
    }

    @Test
    void everySemanticEnvelopeDimensionAndPayloadContentIsFenced() throws Exception {
        JsonNode payload = mapper.readTree("{\"local_order_id\":37,\"quantity\":1}");
        String original = fingerprint(7, payload);

        assertNotEquals(original, fingerprint(8, payload));
        assertNotEquals(original, KdsReplicationFingerprint.compute(
                mapper, 7, "kds_state_changed", "order:37", 10, "cashier-primary", payload));
        assertNotEquals(original, KdsReplicationFingerprint.compute(
                mapper, 7, "order_created", "order:38", 10, "cashier-primary", payload));
        assertNotEquals(original, KdsReplicationFingerprint.compute(
                mapper, 7, "order_created", "order:37", 11, "cashier-primary", payload));
        assertNotEquals(original, KdsReplicationFingerprint.compute(
                mapper, 7, "order_created", "order:37", 10, "cashier-replacement", payload));
        assertNotEquals(original, fingerprint(7,
                mapper.readTree("{\"local_order_id\":37,\"quantity\":2}")));
    }

    private String fingerprint(int shopId, JsonNode payload) {
        return KdsReplicationFingerprint.compute(
                mapper, shopId, "order_created", "order:37", 10, "cashier-primary", payload);
    }
}
