package com.lanf.kds.delivery;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.service.KdsDishServingDurationService;
import com.lanf.kds.service.KdsPushService;
import com.lanf.kds.service.KdsTicketFlagService;
import com.lanf.realtime.CashierEventWebSocketHub;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.PlatformTransactionManager;

import java.sql.ResultSet;
import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D025：明细制作状态下行（ORDER_LINE_STATUS_CHANGED）行为验证。
 * 覆盖：publishLineStatus 成功/失败/空集合；rushOrder 与 refreshOverdueForShop 埋点及负向（未翻转不发布）。
 */
class KdsLineStatusDownlinkTest {

    // ---------- T1: CashierKdsProjectionService.publishLineStatus ----------

    private CashierKdsProjectionService newProjectionService(JdbcTemplate jdbc) {
        return new CashierKdsProjectionService(
                jdbc,
                mock(com.fasterxml.jackson.databind.ObjectMapper.class),
                mock(CashierEventWebSocketHub.class),
                mock(PlatformTransactionManager.class),
                mock(CashierKdsProjectionPublishRetry.class));
    }

    @Test
    void publishLineStatusPersistsDeliveryEventAndWakes() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        CashierKdsProjectionService service = newProjectionService(jdbc);
        com.fasterxml.jackson.databind.ObjectMapper om = mock(com.fasterxml.jackson.databind.ObjectMapper.class);
        ReflectionTestUtils.setField(service, "objectMapper", om);
        CashierEventWebSocketHub hub = mock(CashierEventWebSocketHub.class);
        ReflectionTestUtils.setField(service, "wakeHub", hub);
        when(om.writeValueAsString(any())).thenReturn("{}");
        // loadOrder 走真实 RowMapper（mock ResultSet 提供 order 行）
        when(jdbc.query(anyString(), any(RowMapper.class), anyInt())).thenAnswer(inv -> {
            @SuppressWarnings("unchecked")
            RowMapper<Object> rm = inv.getArgument(1);
            ResultSet rs = mock(ResultSet.class);
            when(rs.getInt("id")).thenReturn(9001);
            when(rs.getInt("shop_id")).thenReturn(1);
            when(rs.getString("order_no")).thenReturn("ORD9001");
            when(rs.getTimestamp("order_time")).thenReturn(new java.sql.Timestamp(1_786_572_600_000L));
            return Collections.singletonList(rm.mapRow(rs, 0));
        });
        when(jdbc.update(anyString(), (Object[]) any())).thenReturn(1);
        when(jdbc.queryForObject(anyString(), eq(Long.class), any())).thenReturn(10241L);

        CashierKdsProjectionService.LineStatusDelta delta =
                new CashierKdsProjectionService.LineStatusDelta(9901, 2, 0, 1, 0, 1, 0, 0, 0, 1_786_572_600_000L);
        service.publishLineStatus(1, 9001, Collections.singletonList(delta));

        verify(jdbc).update(contains("INSERT INTO t_kds_delivery_event"), (Object[]) any());
        verify(jdbc).queryForObject(contains("SELECT id FROM t_kds_delivery_event WHERE event_id=?"),
                eq(Long.class), any());
        verify(hub).broadcastWake(1, 10241L);
    }

    @Test
    void publishLineStatusSkipsEmptyDeltas() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        CashierKdsProjectionService service = newProjectionService(jdbc);
        service.publishLineStatus(1, 9001, Collections.emptyList());
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void publishLineStatusFailureDoesNotThrow() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class), anyInt()))
                .thenThrow(new RuntimeException("db down"));
        CashierKdsProjectionService service = newProjectionService(jdbc);
        CashierKdsProjectionService.LineStatusDelta delta =
                new CashierKdsProjectionService.LineStatusDelta(9901, 1, 1, 0, 0, 0, 0, 0, 0, 1_786_572_600_000L);
        assertDoesNotThrow(() -> service.publishLineStatus(1, 9001, Collections.singletonList(delta)));
    }

    // ---------- T3: rushOrder 埋点 ----------

    @Test
    void rushOrderPublishesLineStatus() {
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        CashierKdsProjectionService projection = mock(CashierKdsProjectionService.class);
        KdsTicketFlagService service = flagService(ticketMapper, projection);

        KdsTicket t = new KdsTicket();
        t.setId(1L);
        t.setOrder_id(2);
        t.setDetail_id(3);
        t.setItem_status(KdsItemStatus.PENDING);
        t.setRush_flag(0);
        t.setOverdue_flag(0);
        t.setAdd_dish_flag(0);
        t.setArchived(0);
        t.setUpdated_at(new Date());
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(t));

        service.rushOrder(1, 2, null);

        verify(projection).publishLineStatus(eq(1), eq(2), anyCollection());
    }

    // ---------- T4: refreshOverdueForShop 埋点 ----------

    @Test
    void refreshOverdueForShopPublishesOnlyFlippedRows() {
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        CashierKdsProjectionService projection = mock(CashierKdsProjectionService.class);
        KdsDishServingDurationService durationService = mock(KdsDishServingDurationService.class);
        KdsTicketFlagService service = flagService(ticketMapper, projection);
        ReflectionTestUtils.setField(service, "servingDurationService", durationService);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(1L);
        ticket.setOrder_id(2);
        ticket.setDetail_id(3);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setOverdue_flag(0);
        ticket.setArchived(0);
        ticket.setCreated_at(new Date(System.currentTimeMillis() - 11 * 60_000L));
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(durationService.resolveSecondsByDetailIds(any(), anyInt(), any()))
                .thenReturn(Collections.singletonMap(3, 600));

        int changed = service.refreshOverdueForShop(7, 600);

        assertTrue(changed > 0, "超时行应被翻转");
        verify(projection).publishLineStatus(eq(7), eq(2), anyCollection());
    }

    @Test
    void refreshOverdueForShopSkipsUnchangedRows() {
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        CashierKdsProjectionService projection = mock(CashierKdsProjectionService.class);
        KdsDishServingDurationService durationService = mock(KdsDishServingDurationService.class);
        KdsTicketFlagService service = flagService(ticketMapper, projection);
        ReflectionTestUtils.setField(service, "servingDurationService", durationService);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(1L);
        ticket.setOrder_id(2);
        ticket.setDetail_id(3);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setOverdue_flag(1); // 已标记超时
        ticket.setArchived(0);
        ticket.setCreated_at(new Date(System.currentTimeMillis() - 11 * 60_000L)); // 仍超时 → cur==next → skip
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(durationService.resolveSecondsByDetailIds(any(), anyInt(), any()))
                .thenReturn(Collections.singletonMap(3, 600));

        service.refreshOverdueForShop(7, 600);

        verify(projection, never()).publishLineStatus(anyInt(), anyInt(), any());
    }

    private KdsTicketFlagService flagService(KdsTicketMapper ticketMapper,
                                             CashierKdsProjectionService projection) {
        KdsTicketFlagService service = new KdsTicketFlagService();
        ReflectionTestUtils.setField(service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(service, "pushService", mock(KdsPushService.class));
        ReflectionTestUtils.setField(service, "servingDurationService", mock(KdsDishServingDurationService.class));
        ReflectionTestUtils.setField(service, "projectionService", projection);
        return service;
    }

    // 编译期引用校验：delta 载荷字段必须存在（防止字段改名后测试静默失效）
    @Test
    void lineStatusDeltaPayloadFieldsExist() {
        CashierKdsProjectionService.LineStatusDelta d =
                new CashierKdsProjectionService.LineStatusDelta(1, 0, 0, 0, 0, 0, 0, 0, 0, 0L);
        assertEquals(1, d.detailId);
        assertEquals(0, d.itemStatus);
        assertEquals(0, d.prepQuantity);
        assertEquals(0, d.cookedQuantity);
        assertEquals(0, d.servedQuantity);
        assertEquals(0, d.rushFlag);
        assertEquals(0, d.overdueFlag);
        assertEquals(0, d.addDishFlag);
        assertEquals(0, d.archived);
        assertEquals(0L, d.updatedAtMs);
    }
}
