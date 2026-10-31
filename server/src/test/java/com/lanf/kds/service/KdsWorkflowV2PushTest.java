package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.realtime.KdsWebSocketHub;
import com.lanf.realtime.WebSocketOutboundDispatcher;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class KdsWorkflowV2PushTest {

    private KdsWorkflowV2Service workflowV2Service;
    private KdsOverviewBoardService overviewBoardService;
    private KdsTicketMapper ticketMapper;
    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private KdsConfigService configService;
    private KdsPushService pushService;

    @BeforeEach
    void setUp() {
        workflowV2Service = new KdsWorkflowV2Service();
        overviewBoardService = mock(KdsOverviewBoardService.class);
        ticketMapper = mock(KdsTicketMapper.class);
        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        configService = mock(KdsConfigService.class);
        pushService = mock(KdsPushService.class);

        ReflectionTestUtils.setField(workflowV2Service, "overviewBoardService", overviewBoardService);
        ReflectionTestUtils.setField(workflowV2Service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(workflowV2Service, "orderService", orderService);
        ReflectionTestUtils.setField(workflowV2Service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(workflowV2Service, "configService", configService);
        ReflectionTestUtils.setField(workflowV2Service, "pushService", pushService);

        Map<String, Integer> mockCounts = new LinkedHashMap<>();
        mockCounts.put(KdsWorkflowQueue.PENDING_PREP, 0);
        mockCounts.put(KdsWorkflowQueue.PENDING_COOK, 2);
        mockCounts.put(KdsWorkflowQueue.READY_SERVE, 0);
        mockCounts.put(KdsWorkflowQueue.DONE, 0);
        when(overviewBoardService.countWorkflowQueues(anyInt(), anyString(), any(), any(), any()))
                .thenReturn(mockCounts);
    }

    @Test
    @DisplayName("测试新订单接单广播：符合 V2 信封规范且包含 22 个必填字段及增量追赶日志")
    void testBroadcastOrderAccepted_NewOrder() {
        int shopId = 1;
        int orderId = 888;

        Order order = new Order();
        order.setId(orderId);
        order.setShop_id(shopId);
        order.setOrder_no("ORD20260914001");
        order.setTable_number("T08");
        order.setDineInOrTakeOut("dine_in");
        order.setPay_time(new Date());

        OrderDetail detail = new OrderDetail();
        detail.setId(101);
        detail.setMId(orderId);
        detail.setDish_id(201);
        detail.setName("烤羊肉串");
        detail.setQuantity("5");
        detail.setSelectedSpicy("微辣");
        detail.setUnit("串");

        KdsTicket ticket = new KdsTicket();
        ticket.setId(1001L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(101);
        ticket.setOrder_no(order.getOrder_no());
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setPrep_quantity(0);
        ticket.setCooked_quantity(0);
        ticket.setServed_quantity(0);
        ticket.setCreated_at(new Date());
        ticket.setUpdated_at(new Date());

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(detail));
        when(configService.isPrepWorkflowEnabled(shopId)).thenReturn(false);

        workflowV2Service.broadcastOrderAccepted(order, null, false);

        ArgumentCaptor<QueryWrapper> queryCaptor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(orderDetailService).list(queryCaptor.capture());
        assertTrue(queryCaptor.getValue().getSqlSegment().contains("mId = "), "OrderDetail 查询列名必须为 mId 而非下划线形式 m_id");

        ArgumentCaptor<Map<String, Object>> envelopeCaptor = ArgumentCaptor.forClass(Map.class);
        verify(pushService, times(1)).broadcastV2Envelope(eq(shopId), envelopeCaptor.capture());

        Map<String, Object> envelope = envelopeCaptor.getValue();
        assertEquals(2, envelope.get("protocol_version"));
        assertEquals("order_accepted", envelope.get("type"));
        assertEquals(shopId, envelope.get("shop_id"));
        assertTrue(((String) envelope.get("event_id")).startsWith("order:888:"));
        assertTrue((Integer) envelope.get("event_seq") > 0);

        // 验证 patches 及 22 个规范字段
        List<Map<String, Object>> patches = (List<Map<String, Object>>) envelope.get("patches");
        assertNotNull(patches);
        assertEquals(1, patches.size());
        Map<String, Object> patch = patches.get(0);
        assertEquals(101, patch.get("detail_id"));
        assertEquals(888, patch.get("order_id"));
        assertEquals(false, patch.get("removed"));

        Map<String, Object> line = (Map<String, Object>) patch.get("line");
        assertNotNull(line);
        assertEquals(101, line.get("detail_id"));
        assertEquals(888, line.get("order_id"));
        assertEquals(201, line.get("dish_id"));
        assertEquals("烤羊肉串", line.get("dish_name"));
        assertEquals(5, line.get("line_quantity"));
        assertEquals(0, line.get("refunded_quantity"));
        assertEquals(0, line.get("prep_remaining"));
        assertEquals(5, line.get("cook_remaining"));
        assertEquals(5, line.get("ready_remaining"));
        assertEquals("dine_in", line.get("fulfillment_bucket"));
        assertEquals("T08", line.get("table_number"));
        assertEquals("ORD20260914001", line.get("order_no"));
        assertEquals(false, line.get("removed"));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, line.get("workflow_queue"));

        // 验证增量日志记录（支持 /kds/v2/changes 追赶）
        KdsDevice device = new KdsDevice();
        device.setShop_id(shopId);
        Map<String, Object> changes = workflowV2Service.getChanges(device, 0);
        List<Map<String, Object>> events = (List<Map<String, Object>>) changes.get("events");
        assertNotNull(events);
        assertFalse(events.isEmpty());
        assertEquals("order_accepted", events.get(events.size() - 1).get("type"));
    }

    @Test
    @DisplayName("测试加菜广播：type 为 order_updated，event_id 以 add: 开头")
    void testBroadcastOrderAccepted_AddDishes() {
        int shopId = 1;
        int orderId = 889;

        Order order = new Order();
        order.setId(orderId);
        order.setShop_id(shopId);
        order.setOrder_no("ORD20260914002");
        order.setTable_number("T09");
        order.setDineInOrTakeOut("takeout");

        OrderDetail detail = new OrderDetail();
        detail.setId(102);
        detail.setMId(orderId);
        detail.setDish_id(202);
        detail.setName("烤生蚝");
        detail.setQuantity("2");

        KdsTicket ticket = new KdsTicket();
        ticket.setId(1002L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(102);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setCreated_at(new Date());
        ticket.setUpdated_at(new Date());

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(detail));

        workflowV2Service.broadcastOrderAccepted(order, Collections.singletonList(102), true);

        ArgumentCaptor<Map<String, Object>> envelopeCaptor = ArgumentCaptor.forClass(Map.class);
        verify(pushService, times(1)).broadcastV2Envelope(eq(shopId), envelopeCaptor.capture());

        Map<String, Object> envelope = envelopeCaptor.getValue();
        assertEquals(2, envelope.get("protocol_version"));
        assertEquals("order_updated", envelope.get("type"));
        assertTrue(((String) envelope.get("event_id")).startsWith("add:889:"));
    }

    @Test
    @DisplayName("新订单事件持久化失败必须向上抛出，禁止提交不可追赶的 KDS 投影")
    void broadcastOrderAccepted_PropagatesPublishFailure() {
        int shopId = 1;
        int orderId = 892;
        Order order = new Order();
        order.setId(orderId);
        order.setShop_id(shopId);
        order.setOrder_no("ORD-PUBLISH-FAIL");

        OrderDetail detail = new OrderDetail();
        detail.setId(104);
        detail.setMId(orderId);
        detail.setDish_id(204);
        detail.setName("事件失败测试菜品");
        detail.setQuantity("1");

        KdsTicket ticket = new KdsTicket();
        ticket.setId(1004L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(104);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setCreated_at(new Date());
        ticket.setUpdated_at(new Date());

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(detail));
        KdsV2EventStore eventStore = mock(KdsV2EventStore.class);
        ReflectionTestUtils.setField(workflowV2Service, "eventStore", eventStore);
        doThrow(new IllegalStateException("event store unavailable"))
                .when(eventStore).append(eq(shopId), anyMap());

        IllegalStateException failure = assertThrows(IllegalStateException.class,
                () -> workflowV2Service.broadcastOrderAccepted(order, null, false));

        assertTrue(failure.getMessage().contains("KDS"));
    }

    @Test
    @DisplayName("WebSocket 快通道失败不回滚已持久化事件，客户端仍可通过 changes 追赶")
    void publishEnvelope_DoesNotFailAfterDurableAppendWhenWebSocketPushFails() {
        int shopId = 1;
        KdsV2EventStore eventStore = mock(KdsV2EventStore.class);
        ReflectionTestUtils.setField(workflowV2Service, "eventStore", eventStore);
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("event_seq", 9);
        envelope.put("event_id", "order:900:9");
        envelope.put("type", "order_accepted");
        envelope.put("shop_id", shopId);
        envelope.put("patches", Collections.emptyList());
        doThrow(new IllegalStateException("socket closed"))
                .when(pushService).broadcastV2Envelope(eq(shopId), anyMap());

        assertDoesNotThrow(() -> workflowV2Service.publishEnvelope(shopId, envelope));

        verify(eventStore).append(eq(shopId), same(envelope));
        verify(pushService).broadcastV2Envelope(eq(shopId), same(envelope));
    }

    @Test
    @DisplayName("测试订单取消广播：所有 patches 带有 removed: true")
    void testBroadcastOrderCancelled() {
        int shopId = 1;
        int orderId = 890;

        Order order = new Order();
        order.setId(orderId);
        order.setShop_id(shopId);
        order.setOrder_no("ORD20260914003");

        OrderDetail d1 = new OrderDetail();
        d1.setId(103);
        d1.setMId(orderId);
        d1.setName("拍黄瓜");
        d1.setQuantity("1");

        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(d1));

        workflowV2Service.broadcastOrderCancelled(shopId, order);

        ArgumentCaptor<Map<String, Object>> envelopeCaptor = ArgumentCaptor.forClass(Map.class);
        verify(pushService, times(1)).broadcastV2Envelope(eq(shopId), envelopeCaptor.capture());

        Map<String, Object> envelope = envelopeCaptor.getValue();
        assertEquals(2, envelope.get("protocol_version"));
        assertEquals("order_cancelled", envelope.get("type"));
        assertTrue(((String) envelope.get("event_id")).startsWith("cancel:890:"));

        List<Map<String, Object>> patches = (List<Map<String, Object>>) envelope.get("patches");
        assertEquals(1, patches.size());
        assertEquals(true, patches.get(0).get("removed"));
        assertEquals(103, patches.get(0).get("detail_id"));
    }

    @Test
    @DisplayName("测试退菜广播：patches 带有 removed: true，type 为 item_refunded")
    void testBroadcastItemRefunded() {
        int shopId = 1;
        int orderId = 891;

        OrderDetail d1 = new OrderDetail();
        d1.setId(104);
        d1.setMId(orderId);
        d1.setName("可乐");
        d1.setQuantity("1");

        when(orderDetailService.listByIds(any())).thenReturn(Collections.singletonList(d1));

        workflowV2Service.broadcastItemRefunded(shopId, orderId, Collections.singletonList(104));

        ArgumentCaptor<Map<String, Object>> envelopeCaptor = ArgumentCaptor.forClass(Map.class);
        verify(pushService, times(1)).broadcastV2Envelope(eq(shopId), envelopeCaptor.capture());

        Map<String, Object> envelope = envelopeCaptor.getValue();
        assertEquals(2, envelope.get("protocol_version"));
        assertEquals("item_refunded", envelope.get("type"));
        assertTrue(((String) envelope.get("event_id")).startsWith("refund:891:"));

        List<Map<String, Object>> patches = (List<Map<String, Object>>) envelope.get("patches");
        assertEquals(1, patches.size());
        assertEquals(true, patches.get(0).get("removed"));
        assertEquals(104, patches.get(0).get("detail_id"));
    }

    @Test
    @DisplayName("测试 WebSocket 协议版本物理隔离：V2 信封仅发向 V2 会话，V1 报文不发向 V2 会话")
    void testWebSocketProtocolIsolation() {
        WebSocketOutboundDispatcher dispatcher = mock(WebSocketOutboundDispatcher.class);
        when(dispatcher.dispatch(any(), any())).thenReturn(true);
        KdsWebSocketHub hub = new KdsWebSocketHub(dispatcher);

        WebSocketSession sessionV1 = mock(WebSocketSession.class);
        when(sessionV1.isOpen()).thenReturn(true);
        Map<String, Object> attrsV1 = new HashMap<>();
        attrsV1.put("kds_protocol_version", 1);
        when(sessionV1.getAttributes()).thenReturn(attrsV1);

        WebSocketSession sessionV2 = mock(WebSocketSession.class);
        when(sessionV2.isOpen()).thenReturn(true);
        Map<String, Object> attrsV2 = new HashMap<>();
        attrsV2.put("kds_protocol_version", 2);
        when(sessionV2.getAttributes()).thenReturn(attrsV2);

        hub.register(sessionV1, 1, "workflow_board");
        hub.register(sessionV2, 1, "workflow_board");

        // 广播 V1 报文
        int sentV1 = hub.broadcastV1(1, "workflow_board", "{\"type\":\"new_order\"}");
        assertEquals(1, sentV1);
        verify(dispatcher, times(1)).dispatch(eq(sessionV1), any(TextMessage.class));
        verify(dispatcher, never()).dispatch(eq(sessionV2), any(TextMessage.class));

        // 广播 V2 信封
        int sentV2 = hub.broadcastV2(1, "workflow_board", "{\"protocol_version\":2}");
        assertEquals(1, sentV2);
        verify(dispatcher, times(1)).dispatch(eq(sessionV2), any(TextMessage.class));
    }
}
