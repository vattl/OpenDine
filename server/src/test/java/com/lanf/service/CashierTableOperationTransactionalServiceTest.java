package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.dto.CashierTableOperationRequest;
import com.lanf.dto.CashierTableOperationResult;
import com.lanf.entity.CashierTableAudit;
import com.lanf.entity.Order;
import com.lanf.entity.Table;
import com.lanf.mapper.CashierTableAuditMapper;
import com.lanf.mapper.CashierTableOperationMapper;
import com.lanf.service.impl.CashierTableOperationTransactionalService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Transactional;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class CashierTableOperationTransactionalServiceTest {

    private CashierTableOperationMapper operationMapper;
    private CashierTableAuditMapper auditMapper;
    private com.lanf.printing.service.PrintDispatcherService printDispatcherService;
    private CashierTableOperationTransactionalService service;

    @BeforeEach
    void setUp() {
        operationMapper = mock(CashierTableOperationMapper.class);
        auditMapper = mock(CashierTableAuditMapper.class);
        printDispatcherService = mock(com.lanf.printing.service.PrintDispatcherService.class);
        service = new CashierTableOperationTransactionalService(operationMapper, auditMapper, new ObjectMapper(), null, printDispatcherService);
    }

    @Test
    void open_shouldCreateShopScopedTableAndAuditSuccess() {
        when(operationMapper.lockTable(7, "A01")).thenReturn(null);
        when(operationMapper.insertTable(any(Table.class))).thenReturn(1);

        CashierTableOperationResult result = service.execute(request("OPEN", "A01", null, "open-1"));

        assertTrue(result.isSuccess());
        verify(operationMapper).insertTable(argThat(t -> t.getShop_id() == 7 && t.getStatus() == 1));
        verify(auditMapper).insert(argThat(a -> "SUCCESS".equals(a.getResult_status())
                && a.getShop_id() == 7 && "A01".equals(a.getSource_table())));
    }

    @Test
    void open_shouldRejectStrayUnsettledOrderEvenWhenTableSaysFree() {
        Table table = table(1, 7, "A01", 0, null);
        when(operationMapper.lockTable(7, "A01")).thenReturn(table);
        when(operationMapper.lockUnsettledOrders(7, "A01"))
                .thenReturn(Collections.singletonList(order(10, 7, "O-1", "A01")));

        CashierTableOperationResult result = service.execute(request("OPEN", "A01", null, "open-2"));

        assertFalse(result.isSuccess());
        assertEquals(409, result.getCode());
        verify(operationMapper, never()).openExistingTable(anyInt(), anyInt(), anyInt(), any());
        verify(auditMapper).insert(argThat(a -> "REJECTED".equals(a.getResult_status())
                && a.getOrder_nos().contains("O-1")));
    }

    @Test
    void clear_shouldCheckEveryUnsettledOrderNotOnlyTableOrderNo() {
        Table table = table(1, 7, "A01", 1, "O-1");
        when(operationMapper.lockTable(7, "A01")).thenReturn(table);
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Arrays.asList(
                order(10, 7, "O-1", "A01"), order(11, 7, "O-2", "A01")));

        CashierTableOperationResult result = service.execute(request("CLEAR", "A01", null, "clear-1"));

        assertFalse(result.isSuccess());
        assertTrue(result.getMessage().contains("2"));
        verify(operationMapper, never()).clearTable(anyInt(), anyInt(), anyInt(), any());
        verify(auditMapper).insert(argThat(a -> a.getOrder_nos().contains("O-1") && a.getOrder_nos().contains("O-2")));
    }

    @Test
    void clear_shouldBeIdempotentWhenTableAlreadyFree() {
        when(operationMapper.lockTable(7, "A01")).thenReturn(table(1, 7, "A01", 0, null));
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Collections.emptyList());

        CashierTableOperationResult result = service.execute(request("CLEAR", "A01", null, "clear-2"));

        assertTrue(result.isSuccess());
        assertTrue(result.isIdempotent());
        verify(operationMapper, never()).clearTable(anyInt(), anyInt(), anyInt(), any());
    }

    @Test
    void clear_shouldClearOpenedTableWhenNoUnsettledOrdersRemain() {
        when(operationMapper.lockTable(7, "A01")).thenReturn(table(1, 7, "A01", 1, "PAID-1"));
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Collections.emptyList());
        when(operationMapper.clearTable(eq(1), eq(7), eq(1), any())).thenReturn(1);

        CashierTableOperationResult result = service.execute(request("CLEAR", "A01", null, "clear-3"));

        assertTrue(result.isSuccess());
        verify(operationMapper).clearTable(eq(1), eq(7), eq(1), any());
        verify(auditMapper).insert(argThat(a -> "SUCCESS".equals(a.getResult_status())
                && a.getBefore_state().contains("PAID-1") && a.getAfter_state().contains("\"status\":0")));
    }

    @Test
    void clear_shouldReleaseCheckedOutTableStatusTwo() {
        when(operationMapper.lockTable(7, "A01")).thenReturn(table(1, 7, "A01", 2, "PAID-1"));
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Collections.emptyList());
        when(operationMapper.clearTable(eq(1), eq(7), eq(2), any())).thenReturn(1);

        CashierTableOperationResult result = service.execute(request("CLEAR", "A01", null, "clear-checked-out"));

        assertTrue(result.isSuccess());
        assertFalse(result.isIdempotent());
        verify(operationMapper).clearTable(eq(1), eq(7), eq(2), any());
    }

    @Test
    void open_shouldRejectCheckedOutTableUntilItIsCleared() {
        when(operationMapper.lockTable(7, "A01")).thenReturn(table(1, 7, "A01", 2, "PAID-1"));
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Collections.emptyList());

        CashierTableOperationResult result = service.execute(request("OPEN", "A01", null, "open-checked-out"));

        assertFalse(result.isSuccess());
        assertEquals(409, result.getCode());
        verify(operationMapper, never()).openExistingTable(anyInt(), anyInt(), anyInt(), any());
    }

    @Test
    void open_shouldRejectOverlongTableNumberBeforeDatabaseMutation() {
        String overlong = "123456789012345678901";

        CashierTableOperationResult result = service.execute(request("OPEN", overlong, null, "open-overlong"));

        assertFalse(result.isSuccess());
        assertEquals(400, result.getCode());
        verifyNoInteractions(operationMapper);
        verify(auditMapper).insert(argThat(a -> "REJECTED".equals(a.getResult_status())));
    }

    @Test
    void duplicateIdempotencyKey_shouldReplayStoredResultWithoutMutatingTables() {
        CashierTableAudit previous = new CashierTableAudit();
        previous.setResult_status("SUCCESS");
        previous.setResult_code(0);
        previous.setReason("开台成功");
        previous.setRequest_fingerprint(sha256("OPEN|A01|null"));
        when(auditMapper.findByRequest(7, "OPEN", "same-key")).thenReturn(previous);

        CashierTableOperationResult result = service.execute(request("OPEN", "A01", null, "same-key"));

        assertTrue(result.isSuccess());
        assertTrue(result.isIdempotent());
        verifyNoInteractions(operationMapper);
        verify(auditMapper, never()).insert(any(CashierTableAudit.class));
    }

    @Test
    void merge_shouldAppendToOccupiedTargetPreserveTargetPointerAndMoveAllSourceOrders() {
        Table source = table(1, 7, "A01", 1, "S-1");
        Table target = table(2, 7, "A02", 1, "T-1");
        when(operationMapper.lockTables(7, "A01", "A02")).thenReturn(Arrays.asList(source, target));
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Arrays.asList(
                order(10, 7, "S-1", "A01"), order(11, 7, "S-2", "A01")));
        when(operationMapper.lockUnsettledOrders(7, "A02"))
                .thenReturn(Collections.singletonList(order(12, 7, "T-1", "A02")));
        when(operationMapper.moveUnsettledOrders(7, "A01", "A02", "T-1")).thenReturn(2);
        when(operationMapper.clearTable(eq(1), eq(7), eq(1), any())).thenReturn(1);
        when(operationMapper.updateTableState(eq(2), eq(7), eq(1), eq("T-1"),
                anyDouble(), any(), isNull())).thenReturn(1);

        CashierTableOperationResult result = service.execute(request("MERGE", "A01", "A02", "merge-1"));

        assertTrue(result.isSuccess());
        verify(operationMapper).moveUnsettledOrders(7, "A01", "A02", "T-1");
        verify(operationMapper).finishSettledOrdersOnTable(eq(7), eq("A01"), any());
        verify(operationMapper).updateTableState(eq(2), eq(7), eq(1), eq("T-1"),
                anyDouble(), any(), isNull());
        verify(auditMapper).insert(argThat(a -> a.getOrder_nos().contains("S-2")
                && a.getAfter_state().contains("T-1")));
    }

    @Test
    void merge_shouldRejectCrossShopOrMissingSourceWithoutChangingAnything() {
        when(operationMapper.lockTables(7, "A01", "A02"))
                .thenReturn(Collections.singletonList(table(2, 7, "A02", 1, null)));

        CashierTableOperationResult result = service.execute(request("MERGE", "A01", "A02", "merge-xshop"));

        assertFalse(result.isSuccess());
        assertEquals(404, result.getCode());
        verify(operationMapper, never()).moveUnsettledOrders(anyInt(), anyString(), anyString());
        verify(auditMapper).insert(argThat(a -> "REJECTED".equals(a.getResult_status())));
    }

    @Test
    void transfer_shouldRepairBothTablePointersAndPreserveOtherSourceOrders() {
        Table source = table(1, 7, "A01", 1, "S-1");
        Table target = table(2, 7, "A02", 0, null);
        Order moved = order(10, 7, "S-1", "A01");
        Order remaining = order(11, 7, "S-2", "A01");
        when(operationMapper.findOrder(7, "S-1")).thenReturn(moved);
        when(operationMapper.lockTables(7, "A01", "A02")).thenReturn(Arrays.asList(source, target));
        when(operationMapper.lockOrder(7, "S-1")).thenReturn(moved);
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Arrays.asList(moved, remaining));
        when(operationMapper.lockUnsettledOrders(7, "A02")).thenReturn(Collections.emptyList());
        when(operationMapper.moveOrder(10, 7, "A01", "A02")).thenReturn(1);
        when(operationMapper.updateTableState(anyInt(), eq(7), anyInt(), any(), anyDouble(), any(), any()))
                .thenReturn(1);

        CashierTableOperationRequest command = request("TRANSFER", null, "A02", "transfer-1");
        command.setOrderNo("S-1");
        CashierTableOperationResult result = service.execute(command);

        assertTrue(result.isSuccess());
        verify(operationMapper).updateTableState(eq(1), eq(7), eq(1), eq("S-2"), anyDouble(), any(), isNull());
        verify(operationMapper).updateTableState(eq(2), eq(7), eq(1), eq("S-1"), anyDouble(), any(), isNull());
        verify(operationMapper, never()).finishSettledOrdersOnTable(anyInt(), anyString(), any());
        verify(auditMapper).insert(argThat(a -> "TRANSFER".equals(a.getAction())
                && a.getAfter_state().contains("S-2") && a.getAfter_state().contains("S-1")));
    }

    @Test
    void transfer_whenSourceBecomesEmpty_shouldFinishSettledOrdersOnSourceTable() {
        Table source = table(1, 7, "A01", 1, "S-1");
        Table target = table(2, 7, "A02", 0, null);
        Order moved = order(10, 7, "S-1", "A01");
        when(operationMapper.findOrder(7, "S-1")).thenReturn(moved);
        when(operationMapper.lockTables(7, "A01", "A02")).thenReturn(Arrays.asList(source, target));
        when(operationMapper.lockOrder(7, "S-1")).thenReturn(moved);
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Collections.singletonList(moved));
        when(operationMapper.lockUnsettledOrders(7, "A02")).thenReturn(Collections.emptyList());
        when(operationMapper.moveOrder(10, 7, "A01", "A02")).thenReturn(1);
        when(operationMapper.updateTableState(anyInt(), eq(7), anyInt(), any(), anyDouble(), any(), any()))
                .thenReturn(1);

        CashierTableOperationRequest command = request("TRANSFER", null, "A02", "transfer-empty-source");
        command.setOrderNo("S-1");
        CashierTableOperationResult result = service.execute(command);

        assertTrue(result.isSuccess());
        verify(operationMapper).finishSettledOrdersOnTable(eq(7), eq("A01"), any());
        verify(operationMapper).updateTableState(eq(1), eq(7), eq(0), isNull(), eq(0.0), any(), any());
    }

    @Test
    void auditFailure_shouldPropagateSoTransactionalProxyCanRollbackBusinessChanges() throws Exception {
        assertNotNull(CashierTableOperationTransactionalService.class
                .getMethod("execute", CashierTableOperationRequest.class).getAnnotation(Transactional.class));
        when(operationMapper.lockTable(7, "A01")).thenReturn(table(1, 7, "A01", 0, null));
        when(operationMapper.lockUnsettledOrders(7, "A01")).thenReturn(Collections.emptyList());
        when(operationMapper.openExistingTable(eq(1), eq(7), eq(0), any())).thenReturn(1);
        when(auditMapper.insert(any(CashierTableAudit.class))).thenThrow(new IllegalStateException("audit unavailable"));

        assertThrows(IllegalStateException.class,
                () -> service.execute(request("OPEN", "A01", null, "rollback-1")));
    }

    private static CashierTableOperationRequest request(String action, String source, String target, String key) {
        CashierTableOperationRequest request = new CashierTableOperationRequest();
        request.setAction(action);
        request.setShopId(7);
        request.setOperatorId(99);
        request.setSourceTable(source);
        request.setTargetTable(target);
        request.setRequestKey(key);
        request.setTraceId("trace-test");
        request.setIp("127.0.0.1");
        return request;
    }

    private static Table table(int id, int shopId, String number, int status, String orderNo) {
        Table table = new Table();
        table.setId(id);
        table.setShop_id(shopId);
        table.setNumber(number);
        table.setStatus(status);
        table.setOrder_no(orderNo);
        return table;
    }

    private static Order order(int id, int shopId, String orderNo, String tableNumber) {
        Order order = new Order();
        order.setId(id);
        order.setShop_id(shopId);
        order.setOrder_no(orderNo);
        order.setTable_number(tableNumber);
        order.setTransac_status("unsettled");
        return order;
    }

    private static String sha256(String value) {
        try {
            byte[] digest = java.security.MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder();
            for (byte b : digest) result.append(String.format("%02x", b));
            return result.toString();
        } catch (Exception e) {
            throw new AssertionError(e);
        }
    }
}
