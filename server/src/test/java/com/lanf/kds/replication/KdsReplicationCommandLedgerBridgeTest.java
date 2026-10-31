package com.lanf.kds.replication;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.controller.OrderController;
import com.lanf.kds.service.KdsCashierAuthorityService;
import com.lanf.kds.service.KdsDishAvailabilityService;
import com.lanf.kds.service.KdsLackService;
import com.lanf.kds.service.KdsReplicatedCommandRecorder;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.impl.OrderDetailRefundService;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsReplicationCommandLedgerBridgeTest {

    @Test
    void kdsStatePayloadDelegatesItsOriginalCommandIdentityToTheSharedRecorder()
            throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        KdsReplicatedCommandRecorder recorder = mock(KdsReplicatedCommandRecorder.class);
        KdsReplicationService service = new KdsReplicationService(
                mock(JdbcTemplate.class), mapper,
                mock(PlatformTransactionManager.class), mock(OrderController.class),
                mock(IDishService.class), mock(IOrderDetailService.class),
                mock(KdsDishAvailabilityService.class),
                mock(KdsCashierAuthorityService.class),
                mock(KdsReplicationAuditService.class), mock(KdsLackService.class),
                mock(IOrderService.class), mock(OrderDetailRefundService.class), recorder);
        JsonNode payload = mapper.readTree("{\"command_id\":\"cmd-lan-1\","
                + "\"operation_type\":\"advance_item\"}");
        JsonNode lines = mapper.readTree("[{\"detail_id\":139}]");
        Map<String, Object> stable = new LinkedHashMap<>();
        stable.put("event_seq", 42L);
        when(recorder.recordApplied(
                7, "cmd-lan-1", "replica-fp", "advance_item", 1234L, lines))
                .thenReturn(stable);

        Map<String, Object> result = service.recordReplicatedCommandIfPresent(
                7, "replica-fp", 1234L, payload, lines);

        assertEquals(42L, result.get("event_seq"));
        verify(recorder).recordApplied(
                7, "cmd-lan-1", "replica-fp", "advance_item", 1234L, lines);
    }
}
