package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsReplicatedCommandRecorderTest {

    @Mock
    private KdsV2CommandLedger ledger;
    @Mock
    private KdsV2EventStore eventStore;
    @Mock
    private KdsOverviewBoardService overview;
    private KdsReplicatedCommandRecorder recorder;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
        recorder = new KdsReplicatedCommandRecorder(
                ledger, eventStore, overview, new ObjectMapper());
    }

    @Test
    void recordsReplicaResultAndCloudChangeWithOneCloudSequence() throws Exception {
        when(eventStore.nextSequence(7)).thenReturn(42L);
        Map<String, Integer> counts = new LinkedHashMap<>();
        counts.put("pending_cook", 3);
        when(overview.countWorkflowQueues(7, "all", null, null)).thenReturn(counts);
        ArrayNode lines = (ArrayNode) new ObjectMapper().readTree("["
                + "{\"detail_id\":139,\"removed\":false,\"dish_name\":\"Beef\"}]");

        Map<String, Object> result = recorder.recordApplied(
                7, "cmd-lan-1", "replica-fp", "advance_item", 1234L, lines);

        assertEquals("cmd-lan-1", result.get("command_id"));
        assertEquals(42L, result.get("event_seq"));
        assertFalse((Boolean) result.get("duplicate"));
        Map<?, ?> patch = (Map<?, ?>) ((java.util.List<?>) result.get("patches")).get(0);
        assertEquals(139, patch.get("detail_id"));
        assertEquals("Beef", ((Map<?, ?>) patch.get("line")).get("dish_name"));
        verify(ledger).recordReplicaApplied(7, "cmd-lan-1", "replica-fp", result);

        ArgumentCaptor<Map<String, Object>> envelope = ArgumentCaptor.forClass(Map.class);
        verify(eventStore).append(eq(7), envelope.capture());
        assertEquals(42L, envelope.getValue().get("event_seq"));
        assertEquals("cmd:cmd-lan-1", envelope.getValue().get("event_id"));
        assertEquals("advance_item", envelope.getValue().get("type"));
    }
}
