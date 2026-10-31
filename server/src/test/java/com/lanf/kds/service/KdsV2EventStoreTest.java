package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsV2EventStoreTest {

    @Mock
    private JdbcTemplate jdbc;
    private KdsV2EventStore store;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
        store = new KdsV2EventStore();
        ReflectionTestUtils.setField(store, "jdbc", jdbc);
        ReflectionTestUtils.setField(store, "objectMapper", new ObjectMapper());
    }

    @Test
    void allocatesNextShopSequenceUnderDatabaseRowLock() {
        when(jdbc.queryForObject(anyString(), eq(Long.class), eq(7))).thenReturn(41L);
        when(jdbc.update(anyString(), eq(42L), eq(7), eq(41L))).thenReturn(1);

        assertEquals(42L, store.nextSequence(7));
    }

    @Test
    void appendsEnvelopeAndPrunesEventsOutsideRetentionWindow() {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("event_seq", 501L);
        envelope.put("event_id", "cmd:501");
        envelope.put("command_id", "cmd-501");
        envelope.put("schema_version", "2.0");
        envelope.put("entity_id", "order:9");
        envelope.put("business_revision", 12L);
        envelope.put("actor_id", "actor:cashier-1");

        store.append(7, envelope);

        verify(jdbc).update(anyString(), eq(7), eq(501L), eq("cmd:501"),
                eq("cmd-501"), eq("2.0"), eq("order:9"), eq(12L), anyString());
        verify(jdbc).update(contains("INSERT IGNORE INTO t_kds_v2_event_archive"), eq(7), eq(1L));
        verify(jdbc).update(contains("DELETE FROM t_kds_v2_event"), eq(7), eq(1L));
    }

    @Test
    void refusesToPersistAnEventWithoutAuditMetadata() {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("event_seq", 1L);
        envelope.put("event_id", "cmd:1");

        org.junit.jupiter.api.Assertions.assertThrows(
                IllegalArgumentException.class, () -> store.append(7, envelope));
    }

    @Test
    void changesRequiresSnapshotWhenClientCursorIsAheadOfAuthority() {
        when(jdbc.queryForObject(anyString(), eq(Long.class), eq(7))).thenReturn(4L);

        KdsV2EventStore.ChangeBatch batch = store.changes(7, 9L);

        assertEquals(4L, batch.getCurrentSequence());
        assertTrue(batch.isSnapshotRequired());
        assertTrue(batch.getEvents().isEmpty());
    }

    @Test
    void changesRequiresSnapshotWhenRequestedHistoryWasPruned() {
        when(jdbc.queryForObject(anyString(), eq(Long.class), eq(7))).thenReturn(700L, 201L);

        KdsV2EventStore.ChangeBatch batch = store.changes(7, 100L);

        assertTrue(batch.isSnapshotRequired());
        assertTrue(batch.getEvents().isEmpty());
    }

    @Test
    void emptyStoreStartsAtSequenceZeroWithoutSnapshot() {
        when(jdbc.queryForObject(anyString(), eq(Long.class), eq(7))).thenReturn(null);

        KdsV2EventStore.ChangeBatch batch = store.changes(7, 0L);

        assertEquals(0L, batch.getCurrentSequence());
        assertFalse(batch.isSnapshotRequired());
        assertEquals(Collections.emptyList(), batch.getEvents());
    }

    @Test
    void changesReturnsPersistedEventsInDatabaseOrder() {
        when(jdbc.queryForObject(anyString(), eq(Long.class), eq(7))).thenReturn(5L, 3L);
        Map<String, Object> first = new LinkedHashMap<>();
        first.put("event_json", "{\"event_seq\":4,\"event_id\":\"cmd:4\"}");
        Map<String, Object> second = new LinkedHashMap<>();
        second.put("event_json", "{\"event_seq\":5,\"event_id\":\"cmd:5\"}");
        when(jdbc.queryForList(anyString(), eq(7), eq(3L))).thenReturn(Arrays.asList(first, second));

        KdsV2EventStore.ChangeBatch batch = store.changes(7, 3L);

        assertFalse(batch.isSnapshotRequired());
        assertEquals(2, batch.getEvents().size());
        assertEquals(4, batch.getEvents().get(0).get("event_seq"));
        assertEquals(5, batch.getEvents().get(1).get("event_seq"));
    }
}
