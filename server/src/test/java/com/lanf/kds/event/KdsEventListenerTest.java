package com.lanf.kds.event;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.kds.service.KdsPushService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

/**
 * 事件监听器 → WS 推送映射（差距 A/B 验证）。
 */
class KdsEventListenerTest {

    @Mock
    private KdsPushService pushService;

    @Mock
    private CashierKdsProjectionService cashierKdsProjectionService;

    @InjectMocks
    private KdsEventListener listener;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
    }

    @Test
    void orderStatusChanged_broadcastsWithNullScreenTag() {
        KdsOrderStatusChangedEvent e = new KdsOrderStatusChangedEvent(this, 1, 100, "NO100", 20, 40);
        listener.recordOrderClosed(e);
        listener.onOrderStatusChanged(e);

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(pushService).orderStatusChanged(eq(1), isNull(), eq(40), captor.capture());
        Map<String, Object> payload = captor.getValue();
        assertEquals(100, payload.get("order_id"));
        assertEquals("NO100", payload.get("order_no"));
        assertEquals(20, payload.get("from_status"));
        assertEquals(40, payload.get("kds_order_status"));
    }

    @Test
    void orderFirstBecomesAllDone_publishesClosedOrderToCashier() {
        KdsOrderStatusChangedEvent e = new KdsOrderStatusChangedEvent(this, 1, 100, "NO100", 20, 40);

        listener.recordOrderClosed(e);
        listener.onOrderStatusChanged(e);

        verify(cashierKdsProjectionService).publishAfterCommit(
                eq(100), eq("ORDER_CLOSED"), isNull(), isNull(), isNull());
    }

    @Test
    void orderNotAllDone_doesNotPublishClosedOrderToCashier() {
        listener.recordOrderClosed(
                new KdsOrderStatusChangedEvent(this, 1, 100, "NO100", 10, 20));

        verify(cashierKdsProjectionService, never()).publishAfterCommit(
                anyInt(), anyString(), isNull(), isNull(), isNull());
    }

    @Test
    void kdsBroadcastFailure_doesNotBlockCashierClosedOrderDelivery() {
        doThrow(new IllegalStateException("websocket unavailable"))
                .when(pushService).orderStatusChanged(eq(1), isNull(), eq(40), anyMap());

        listener.recordOrderClosed(
                new KdsOrderStatusChangedEvent(this, 1, 100, "NO100", 20, 40));
        listener.onOrderStatusChanged(
                new KdsOrderStatusChangedEvent(this, 1, 100, "NO100", 20, 40));

        verify(cashierKdsProjectionService).publishAfterCommit(
                eq(100), eq("ORDER_CLOSED"), isNull(), isNull(), isNull());
    }

    @Test
    void itemStatusChanged_nonVoid_sendsUpdateOrder() {
        Map<String, Object> payload = new HashMap<>();
        payload.put("line_quantity", 2);
        KdsItemStatusChangedEvent e = new KdsItemStatusChangedEvent(
                this, 1, 55, 100, "meat_grill", 0, 2, "ready_serve", payload);
        listener.onItemStatusChanged(e);

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(pushService).updateOrder(eq(1), eq("meat_grill"), captor.capture());
        assertEquals(55, captor.getValue().get("detail_id"));
        assertEquals(100, captor.getValue().get("order_id"));
        assertEquals("ready_serve", captor.getValue().get("workflow_queue"));
        verify(pushService, never()).cancelItem(anyInt(), anyString(), anyMap());
    }

    @Test
    void itemStatusChanged_void_sendsCancelItem() {
        KdsItemStatusChangedEvent e = new KdsItemStatusChangedEvent(
                this, 1, 55, 100, "meat_grill", 1, KdsItemStatus.VOID, null, Collections.emptyMap());
        listener.onItemStatusChanged(e);

        verify(pushService).cancelItem(eq(1), eq("meat_grill"), anyMap());
        verify(pushService, never()).updateOrder(anyInt(), anyString(), anyMap());
    }

    @Test
    void configChanged_broadcasts() {
        Map<String, Object> fields = new HashMap<>();
        fields.put("sla_minutes", 15);
        listener.onConfigChanged(new KdsConfigChangedEvent(this, 1, fields));
        verify(pushService).configChanged(eq(1), anyMap());
    }
}
