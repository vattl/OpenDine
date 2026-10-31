package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.MockitoAnnotations;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.clearInvocations;

class KdsV2CommandLedgerTest {

    @Mock
    private JdbcTemplate jdbc;
    private KdsV2CommandLedger ledger;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
        ledger = new KdsV2CommandLedger();
        ReflectionTestUtils.setField(ledger, "jdbc", jdbc);
        ReflectionTestUtils.setField(ledger, "objectMapper", new ObjectMapper());
    }

    @Test
    void firstClaimExecutesAndCompletionRequiresOwnedRow() {
        when(jdbc.update(anyString(), eq(7), eq("cmd-1"), anyString(), anyString(),
                anyString(), anyString(), anyString())).thenReturn(1);
        when(jdbc.update(anyString(), anyString(), eq(7), eq("cmd-1"))).thenReturn(1);

        KdsV2CommandLedger.Claim claim = ledger.claim(7, "cmd-1", "test", "KDS", "advance_item", "2.0", command("cmd-1", 1));
        assertTrue(claim.shouldExecute());
        verify(jdbc).update(contains("INSERT IGNORE"), eq(7), eq("cmd-1"),
                anyString(), anyString(), anyString(), anyString(), anyString());

        ledger.complete(7, "cmd-1", result("cmd-1"));
    }

    @Test
    void duplicateSameFingerprintReplaysStableResult() {
        Map<String, Object> request = command("cmd-1", 1);
        when(jdbc.update(anyString(), eq(7), eq("cmd-1"), anyString(), anyString(),
                anyString(), anyString(), anyString())).thenReturn(1);
        String fingerprint = ledger.claim(7, "cmd-1", "test", "KDS", "advance_item", "2.0", request).getFingerprint();

        when(jdbc.update(anyString(), eq(7), eq("cmd-1"), anyString(), anyString(),
                anyString(), anyString(), anyString())).thenReturn(0);
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("request_fingerprint", fingerprint);
        row.put("status", "APPLIED");
        row.put("result_json", "{\"command_id\":\"cmd-1\",\"event_seq\":9}");
        when(jdbc.queryForMap(anyString(), eq(7), eq("cmd-1"))).thenReturn(row);

        KdsV2CommandLedger.Claim replay = ledger.claim(7, "cmd-1", "test", "KDS", "advance_item", "2.0", request);
        assertFalse(replay.shouldExecute());
        assertEquals(9, replay.getResult().get("event_seq"));
    }

    @Test
    void sameIdWithDifferentPayloadIsRejected() {
        when(jdbc.update(anyString(), eq(7), eq("cmd-1"), anyString(), anyString(),
                anyString(), anyString(), anyString())).thenReturn(0);
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("request_fingerprint", "different");
        row.put("status", "APPLIED");
        row.put("result_json", "{}");
        when(jdbc.queryForMap(anyString(), eq(7), eq("cmd-1"))).thenReturn(row);

        assertThrows(KdsV2CommandConflictException.class,
                () -> ledger.claim(7, "cmd-1", "test", "KDS", "advance_item", "2.0", command("cmd-1", 2)));
    }

    @Test
    void oversizedCommandIdIsRejectedBeforeDatabaseWrite() {
        String commandId = String.join("", java.util.Collections.nCopies(129, "x"));

        assertThrows(IllegalArgumentException.class,
                () -> ledger.claim(7, commandId, "test", "KDS", "advance_item", "2.0", command(commandId, 1)));
    }

    @Test
    void resolutionReturnsAppliedStableResult() {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("status", "APPLIED");
        row.put("result_json", "{\"command_id\":\"cmd-1\",\"event_seq\":9}");
        when(jdbc.queryForList(anyString(), eq(7), eq("cmd-1")))
                .thenReturn(java.util.Collections.singletonList(row));

        Map<String, Object> resolution = ledger.resolve(7, "cmd-1");

        assertEquals("APPLIED", resolution.get("status"));
        assertEquals(9, ((Map<?, ?>) resolution.get("result")).get("event_seq"));
    }

    @Test
    void rejectedClaimReplaysTheSameStableBusinessFailure() {
        Map<String, Object> request = command("cmd-rejected", 1);
        when(jdbc.update(anyString(), eq(7), eq("cmd-rejected"), anyString(), anyString(),
                anyString(), anyString(), anyString())).thenReturn(1);
        String fingerprint = ledger.claim(7, "cmd-rejected", "test", "KDS",
                "advance_item", "2.0", request).getFingerprint();
        when(jdbc.update(anyString(), eq(7), eq("cmd-rejected"), anyString(), anyString(),
                anyString(), anyString(), anyString())).thenReturn(0);
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("request_fingerprint", fingerprint);
        row.put("status", "REJECTED");
        row.put("result_json", "{\"command_id\":\"cmd-rejected\",\"status\":\"REJECTED\",\"http_status\":409,\"code\":4090,\"message\":\"版本冲突\"}");
        when(jdbc.queryForMap(anyString(), eq(7), eq("cmd-rejected"))).thenReturn(row);

        KdsV2RejectedCommandException rejected = assertThrows(
                KdsV2RejectedCommandException.class,
                () -> ledger.claim(7, "cmd-rejected", "test", "KDS",
                        "advance_item", "2.0", request));

        assertEquals(409, rejected.getHttpStatus());
        assertEquals(4090, rejected.getBusinessCode());
        assertEquals("版本冲突", rejected.getMessage());
    }

    @Test
    void recordsRejectedResultAsShopScopedTerminalRow() {
        when(jdbc.update(anyString(), eq(7), eq("cmd-rejected"), anyString(),
                anyString(), anyString(), anyString(), anyString(), anyString())).thenReturn(1);

        ledger.recordRejected(7, "cmd-rejected", "DEV001", "KDS",
                "advance_item", "2.0", command("cmd-rejected", 1),
                409, 4090, "版本冲突");

        verify(jdbc).update(contains("'REJECTED'"), eq(7), eq("cmd-rejected"),
                eq("DEV001"), eq("KDS"), eq("advance_item"), anyString(),
                eq("2.0"), contains("\"status\":\"REJECTED\""));
    }

    @Test
    void resolutionReturnsRejectedStableResult() {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("status", "REJECTED");
        row.put("result_json", "{\"command_id\":\"cmd-rejected\",\"status\":\"REJECTED\",\"http_status\":400,\"code\":4000,\"message\":\"参数错误\"}");
        when(jdbc.queryForList(anyString(), eq(7), eq("cmd-rejected")))
                .thenReturn(java.util.Collections.singletonList(row));

        Map<String, Object> resolution = ledger.resolve(7, "cmd-rejected");

        assertEquals("REJECTED", resolution.get("status"));
        assertEquals(4000, ((Map<?, ?>) resolution.get("result")).get("code"));
    }

    @Test
    void resolutionReturnsNotFoundWithoutInventingAResult() {
        when(jdbc.queryForList(anyString(), eq(7), eq("cmd-missing")))
                .thenReturn(java.util.Collections.emptyList());

        Map<String, Object> resolution = ledger.resolve(7, "cmd-missing");

        assertEquals("NOT_FOUND", resolution.get("status"));
        assertFalse(resolution.containsKey("result"));
    }

    @Test
    void replicatedCommandCreatesAnAppliedStableResultWithoutAnExecutingWindow() {
        when(jdbc.update(anyString(), eq(7), eq("cmd-lan-1"), anyString(), anyString(), anyString()))
                .thenReturn(1);

        ledger.recordReplicaApplied(7, "cmd-lan-1", "replication-fingerprint", result("cmd-lan-1"));

        verify(jdbc).update(contains("'APPLIED'"), eq(7), eq("cmd-lan-1"),
                anyString(), anyString(), anyString());
    }

    @Test
    void replicatedCommandNeverOverwritesAnExistingDifferentCommandClaim() {
        when(jdbc.update(anyString(), eq(7), eq("cmd-lan-1"), anyString(), anyString(), anyString()))
                .thenReturn(0);
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("request_fingerprint", "different");
        row.put("status", "APPLIED");
        row.put("result_json", "{\"command_id\":\"cmd-lan-1\"}");
        when(jdbc.queryForMap(anyString(), eq(7), eq("cmd-lan-1"))).thenReturn(row);

        assertThrows(KdsV2CommandConflictException.class,
                () -> ledger.recordReplicaApplied(7, "cmd-lan-1",
                        "replication-fingerprint", result("cmd-lan-1")));
    }

    @Test
    void duplicateReplicaKeepsTheFirstStableResult() {
        when(jdbc.update(anyString(), eq(7), eq("cmd-lan-1"), anyString(), anyString(), anyString()))
                .thenReturn(1);
        ledger.recordReplicaApplied(
                7, "cmd-lan-1", "replication-fingerprint", result("cmd-lan-1"));
        ArgumentCaptor<String> fingerprint = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(anyString(), eq(7), eq("cmd-lan-1"),
                fingerprint.capture(), anyString(), anyString());

        clearInvocations(jdbc);
        when(jdbc.update(anyString(), eq(7), eq("cmd-lan-1"), anyString(), anyString(), anyString()))
                .thenReturn(0);
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("request_fingerprint", fingerprint.getValue());
        row.put("status", "APPLIED");
        row.put("result_json", "{\"command_id\":\"cmd-lan-1\",\"event_seq\":1}");
        when(jdbc.queryForMap(anyString(), eq(7), eq("cmd-lan-1"))).thenReturn(row);
        Map<String, Object> later = result("cmd-lan-1");
        later.put("event_seq", 99);

        ledger.recordReplicaApplied(
                7, "cmd-lan-1", "replication-fingerprint", later);

        verify(jdbc).queryForMap(anyString(), eq(7), eq("cmd-lan-1"));
    }

    @Test
    void resolveFindsArchivedCommandWhenHotTableMisses() {
        when(jdbc.queryForList(contains("FROM t_kds_v2_command WHERE"), eq(7), eq("cmd-archived-1")))
                .thenReturn(Collections.emptyList());
        Map<String, Object> archRow = new LinkedHashMap<>();
        archRow.put("status", "APPLIED");
        archRow.put("result_json", "{\"command_id\":\"cmd-archived-1\",\"event_seq\":88}");
        when(jdbc.queryForList(contains("FROM t_kds_v2_command_archive WHERE"), eq(7), eq("cmd-archived-1")))
                .thenReturn(Collections.singletonList(archRow));

        Map<String, Object> resolution = ledger.resolve(7, "cmd-archived-1");
        assertEquals("APPLIED", resolution.get("status"));
        assertEquals(Boolean.TRUE, resolution.get("archived"));
        Map<String, Object> result = (Map<String, Object>) resolution.get("result");
        assertEquals("cmd-archived-1", result.get("command_id"));
        assertEquals(88, result.get("event_seq"));
    }

    @Test
    void claimReplaysArchivedCommandWhenSameFingerprint() {
        Map<String, Object> request = command("cmd-archived-2", 1);
        when(jdbc.update(contains("INSERT IGNORE INTO t_kds_v2_command"), eq(7), eq("cmd-archived-2"),
                anyString(), anyString(), anyString(), anyString(), anyString())).thenReturn(1);
        Map<String, Object> archRow = new LinkedHashMap<>();
        archRow.put("request_fingerprint", ReflectionTestUtils.invokeMethod(ledger, "fingerprint", 7, request));
        archRow.put("status", "APPLIED");
        archRow.put("result_json", "{\"command_id\":\"cmd-archived-2\",\"event_seq\":99}");
        when(jdbc.queryForList(contains("FROM t_kds_v2_command_archive"), eq(7), eq("cmd-archived-2")))
                .thenReturn(Collections.singletonList(archRow));

        KdsV2CommandLedger.Claim claim = ledger.claim(7, "cmd-archived-2", "test", "KDS", "advance_item", "2.0", request);
        assertFalse(claim.shouldExecute());
        assertEquals("cmd-archived-2", claim.getResult().get("command_id"));
        verify(jdbc).update(contains("DELETE FROM t_kds_v2_command WHERE shop_id=? AND command_id=? AND status='EXECUTING'"),
                eq(7), eq("cmd-archived-2"));
    }

    private static Map<String, Object> command(String id, int quantity) {
        Map<String, Object> target = new LinkedHashMap<>();
        target.put("detail_id", 10);
        target.put("from_queue", "pending_cook");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("command_id", id);
        body.put("type", "advance_item");
        body.put("target", target);
        body.put("quantity", quantity);
        return body;
    }

    private static Map<String, Object> result(String id) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("command_id", id);
        result.put("event_seq", 1);
        return result;
    }
}
