package com.lanf.kds.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Persistent, shop-scoped sequence and bounded change log for the KDS V2 protocol. */
@Service
public class KdsV2EventStore {

    private static final long RETAINED_EVENTS_PER_SHOP = 500L;

    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private ObjectMapper objectMapper;

    /** Must be called inside the workflow transaction. The cursor row lock serializes all writers for a shop. */
    public long nextSequence(int shopId) {
        jdbc.update(
                "INSERT INTO t_kds_v2_event_cursor (shop_id,event_seq,updated_at) VALUES (?,0,NOW()) "
                        + "ON DUPLICATE KEY UPDATE shop_id=VALUES(shop_id)",
                shopId);
        Long current = jdbc.queryForObject(
                "SELECT event_seq FROM t_kds_v2_event_cursor WHERE shop_id=? FOR UPDATE",
                Long.class, shopId);
        if (current == null || current < 0) {
            throw new KdsV2StorageException("KDS event cursor is invalid");
        }
        long next = Math.addExact(current, 1L);
        int updated = jdbc.update(
                "UPDATE t_kds_v2_event_cursor SET event_seq=?,updated_at=NOW() "
                        + "WHERE shop_id=? AND event_seq=?",
                next, shopId, current);
        if (updated != 1) {
            throw new KdsV2StorageException("KDS event cursor update lost its row lock");
        }
        return next;
    }

    public void append(int shopId, Map<String, Object> envelope) {
        long sequence = requiredLong(envelope.get("event_seq"), "event_seq");
        String eventId = requiredText(envelope.get("event_id"), "event_id");
        String commandId = requiredText(envelope.get("command_id"), "command_id");
        String schemaVersion = requiredText(envelope.get("schema_version"), "schema_version");
        String entityId = requiredText(envelope.get("entity_id"), "entity_id");
        long bizRev = requiredNonNegativeLong(
                envelope.get("business_revision"), "business_revision");
        String actorId = requiredText(envelope.get("actor_id"), "actor_id");
        
        try {
            jdbc.update(
                    "INSERT INTO t_kds_v2_event (shop_id,event_seq,event_id,command_id,schema_version,entity_id,business_revision,event_json,created_at) "
                            + "VALUES (?,?,?,?,?,?,?,?,NOW())",
                    shopId, sequence, eventId, commandId, schemaVersion, entityId, bizRev, objectMapper.writeValueAsString(envelope));
            long pruneThrough = sequence - RETAINED_EVENTS_PER_SHOP;
            if (pruneThrough > 0) {
                try {
                    jdbc.update(
                            "INSERT IGNORE INTO t_kds_v2_event_archive "
                                    + "(shop_id,event_seq,event_id,command_id,schema_version,entity_id,business_revision,event_json,created_at,archived_at) "
                                    + "SELECT shop_id,event_seq,event_id,command_id,schema_version,entity_id,business_revision,event_json,created_at,NOW() "
                                    + "FROM t_kds_v2_event WHERE shop_id=? AND event_seq<=?",
                            shopId, pruneThrough);
                } catch (Exception ignored) {
                    // Non-fatal if archive table is missing or transient
                }
                jdbc.update(
                        "DELETE FROM t_kds_v2_event WHERE shop_id=? AND event_seq<=?",
                        shopId, pruneThrough);
            }
        } catch (KdsV2StorageException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new KdsV2StorageException("KDS event could not be persisted", ex);
        }
    }

    public long currentSequence(int shopId) {
        Long current = jdbc.queryForObject(
                "SELECT MAX(event_seq) FROM t_kds_v2_event_cursor WHERE shop_id=?",
                Long.class, shopId);
        return current == null ? 0L : current;
    }

    public ChangeBatch changes(int shopId, long afterSequence) {
        if (afterSequence < 0) {
            throw new IllegalArgumentException("after_seq 不能小于 0");
        }
        long current = currentSequence(shopId);
        if (afterSequence > current) {
            return new ChangeBatch(current, true, Collections.emptyList());
        }
        if (afterSequence == current) {
            return new ChangeBatch(current, false, Collections.emptyList());
        }

        Long minimum = jdbc.queryForObject(
                "SELECT MIN(event_seq) FROM t_kds_v2_event WHERE shop_id=?",
                Long.class, shopId);
        if (minimum == null || afterSequence < minimum - 1L) {
            return new ChangeBatch(current, true, Collections.emptyList());
        }

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT event_json FROM t_kds_v2_event WHERE shop_id=? AND event_seq>? "
                        + "ORDER BY event_seq ASC LIMIT 500",
                shopId, afterSequence);
        List<Map<String, Object>> events = new ArrayList<>(rows.size());
        for (Map<String, Object> row : rows) {
            events.add(readEnvelope(row.get("event_json")));
        }
        return new ChangeBatch(current, false, events);
    }

    private Map<String, Object> readEnvelope(Object json) {
        if (json == null) {
            throw new KdsV2StorageException("stored KDS event is missing its payload");
        }
        try {
            return objectMapper.readValue(String.valueOf(json), new TypeReference<Map<String, Object>>() { });
        } catch (Exception ex) {
            throw new KdsV2StorageException("stored KDS event payload is invalid", ex);
        }
    }

    private static long requiredLong(Object value, String field) {
        if (!(value instanceof Number) || ((Number) value).longValue() <= 0) {
            throw new IllegalArgumentException(field + " must be a positive integer");
        }
        return ((Number) value).longValue();
    }

    private static String requiredText(Object value, String field) {
        String text = value == null ? "" : String.valueOf(value).trim();
        if (text.isEmpty() || text.length() > 128) {
            throw new IllegalArgumentException(field + " must contain 1 to 128 characters");
        }
        return text;
    }

    private static long requiredNonNegativeLong(Object value, String field) {
        if (!(value instanceof Number) || ((Number) value).longValue() < 0) {
            throw new IllegalArgumentException(field + " must be a non-negative integer");
        }
        return ((Number) value).longValue();
    }

    public static final class ChangeBatch {
        private final long currentSequence;
        private final boolean snapshotRequired;
        private final List<Map<String, Object>> events;

        ChangeBatch(long currentSequence, boolean snapshotRequired, List<Map<String, Object>> events) {
            this.currentSequence = currentSequence;
            this.snapshotRequired = snapshotRequired;
            this.events = new ArrayList<>(events);
        }

        public long getCurrentSequence() {
            return currentSequence;
        }

        public boolean isSnapshotRequired() {
            return snapshotRequired;
        }

        public List<Map<String, Object>> getEvents() {
            List<Map<String, Object>> copy = new ArrayList<>(events.size());
            for (Map<String, Object> event : events) copy.add(new LinkedHashMap<>(event));
            return copy;
        }
    }
}
