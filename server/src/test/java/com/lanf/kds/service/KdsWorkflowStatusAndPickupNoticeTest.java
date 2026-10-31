package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsFlowBatchStatus;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsFlowBatch;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.event.KdsEventListener;
import com.lanf.kds.event.KdsOrderStatusChangedEvent;
import com.lanf.kds.mapper.KdsFlowBatchMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class KdsWorkflowStatusAndPickupNoticeTest {

    private KdsFlowBatchService flowBatchService;
    private KdsDetailStatusResolver detailStatusResolver;
    private KdsCustomerPickupNoticeService customerPickupNoticeService;
    private KdsEventListener eventListener;

    private KdsTicketMapper ticketMapper;
    private KdsFlowBatchMapper batchMapper;
    private KdsOrderStatusAggregator orderStatusAggregator;
    private IOrderService orderService;
    private DishMenuPushService dishMenuPushService;
    private KdsPushService kdsPushService;

    @BeforeEach
    void setUp() {
        flowBatchService = new KdsFlowBatchService();
        ticketMapper = mock(KdsTicketMapper.class);
        batchMapper = mock(KdsFlowBatchMapper.class);
        orderStatusAggregator = mock(KdsOrderStatusAggregator.class);
        ReflectionTestUtils.setField(flowBatchService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(flowBatchService, "batchMapper", batchMapper);
        ReflectionTestUtils.setField(flowBatchService, "orderStatusAggregator", orderStatusAggregator);

        detailStatusResolver = new KdsDetailStatusResolver();
        ReflectionTestUtils.setField(detailStatusResolver, "ticketMapper", ticketMapper);

        customerPickupNoticeService = new KdsCustomerPickupNoticeService();
        orderService = mock(IOrderService.class);
        dishMenuPushService = mock(DishMenuPushService.class);
        kdsPushService = mock(KdsPushService.class);
        ReflectionTestUtils.setField(customerPickupNoticeService, "orderService", orderService);
        ReflectionTestUtils.setField(customerPickupNoticeService, "dishMenuPushService", dishMenuPushService);
        ReflectionTestUtils.setField(customerPickupNoticeService, "kdsPushService", kdsPushService);

        eventListener = new KdsEventListener();
        ReflectionTestUtils.setField(eventListener, "pushService", kdsPushService);
        ReflectionTestUtils.setField(eventListener, "customerPickupNoticeService", customerPickupNoticeService);
    }

    @Test
    @DisplayName("菜品在待传菜(ready_serve)中不属于已出餐：item_status为COOKING，archived为0，文案为待传菜")
    void testReadyServeIsNotDoneOrServed() {
        long ticketId = 100L;
        KdsTicket ticket = new KdsTicket();
        ticket.setId(ticketId);
        ticket.setOrder_id(501);
        ticket.setShop_id(1);
        ticket.setDetail_id(1001);
        when(ticketMapper.selectById(ticketId)).thenReturn(ticket);

        // 模拟批次：2份已制作完成，进入 READY_SERVE 队列，未传菜
        KdsFlowBatch batch = new KdsFlowBatch();
        batch.setId(1L);
        batch.setTicket_id(ticketId);
        batch.setQuantity(2);
        batch.setQueue_status(KdsFlowBatchStatus.READY_SERVE);
        when(batchMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(batch));

        flowBatchService.syncTicketAggregates(ticketId);

        // 验证：菜品未传菜完成前，绝不可置为 DONE (2) 或 archived=1
        assertEquals(KdsItemStatus.COOKING, ticket.getItem_status(), "待传菜状态下 item_status 应为 COOKING (1)");
        assertEquals(0, ticket.getArchived(), "待传菜状态下 archived 应为 0");
        assertEquals(2, ticket.getCooked_quantity());
        assertEquals(0, ticket.getServed_quantity());

        // 验证：通过 KdsDetailStatusResolver 解析明细状态时，文案必须为「待传菜」，绝不可为「已完成」或「已出餐」
        OrderDetail detail = new OrderDetail();
        detail.setId(1001);
        detail.setQuantity("2");
        detailStatusResolver.enrichDetails(Collections.singletonList(detail), Collections.singletonMap(1001, ticket));

        assertEquals(KdsItemStatus.COOKING, detail.getKds_item_status());
        assertEquals("待传菜", detail.getKds_status_text());
        assertEquals(0, detail.getKds_served_quantity());
    }

    @Test
    @DisplayName("菜品传菜完成进入已完成(done)才算已出餐：item_status为DONE，archived为1，文案为已完成")
    void testDoneIsServed() {
        long ticketId = 101L;
        KdsTicket ticket = new KdsTicket();
        ticket.setId(ticketId);
        ticket.setOrder_id(501);
        ticket.setShop_id(1);
        ticket.setDetail_id(1002);
        when(ticketMapper.selectById(ticketId)).thenReturn(ticket);

        // 模拟批次：2份传菜完成，进入 DONE 队列
        KdsFlowBatch batch = new KdsFlowBatch();
        batch.setId(2L);
        batch.setTicket_id(ticketId);
        batch.setQuantity(2);
        batch.setQueue_status(KdsFlowBatchStatus.DONE);
        when(batchMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(batch));

        flowBatchService.syncTicketAggregates(ticketId);

        // 验证：传菜完成进入已完成，置为 DONE (2) 并 archived=1
        assertEquals(KdsItemStatus.DONE, ticket.getItem_status(), "已完成状态下 item_status 应为 DONE (2)");
        assertEquals(1, ticket.getArchived(), "已完成状态下 archived 应为 1");
        assertEquals(2, ticket.getCooked_quantity());
        assertEquals(2, ticket.getServed_quantity());
        assertNotNull(ticket.getDone_at());

        // 验证：通过 KdsDetailStatusResolver 解析明细状态为「已完成」
        OrderDetail detail = new OrderDetail();
        detail.setId(1002);
        detail.setQuantity("2");
        detailStatusResolver.enrichDetails(Collections.singletonList(detail), Collections.singletonMap(1002, ticket));

        assertEquals(KdsItemStatus.DONE, detail.getKds_item_status());
        assertEquals("已完成", detail.getKds_status_text());
        assertEquals(2, detail.getKds_served_quantity());
    }

    @Test
    @DisplayName("所有菜品完成自动通知客户取餐：更新order.notice=1并广播WebSocket")
    void testAutoNotifyCustomerPickup() {
        int shopId = 5;
        int orderId = 888;
        Order order = new Order();
        order.setId(orderId);
        order.setOrder_no("ORD20261025001");
        order.setTable_number("A08");
        order.setDineInOrTakeOut("打包");
        order.setNotice(0);
        when(orderService.getById(orderId)).thenReturn(order);

        boolean notified = customerPickupNoticeService.notifyCustomerPickup(shopId, orderId);
        assertTrue(notified, "首次出餐完成应触发通知");
        assertEquals(1, order.getNotice(), "订单 notice 应被更新为 1");
        verify(orderService).updateById(order);
        verify(dishMenuPushService).notifyMealPickupReady(eq(shopId), eq(orderId), eq("ORD20261025001"), eq("A08"), eq("打包"), eq("888"));
        verify(kdsPushService).orderStatusChanged(eq(shopId), isNull(), eq(KdsOrderStatus.ALL_DONE), anyMap());

        // 验证幂等性：已通知过的单再次调用，直接跳过防重
        boolean secondCall = customerPickupNoticeService.notifyCustomerPickup(shopId, orderId);
        assertFalse(secondCall, "已通知过的单不应重复发送");
        verify(orderService, times(1)).updateById(order);
    }

    @Test
    @DisplayName("KdsEventListener 监听到 ALL_DONE 事件自动触发取餐通知")
    void testEventListenerTriggersPickupNotice() {
        int shopId = 5;
        int orderId = 999;
        Order order = new Order();
        order.setId(orderId);
        order.setOrder_no("ORD20261025002");
        order.setNotice(0);
        when(orderService.getById(orderId)).thenReturn(order);

        KdsOrderStatusChangedEvent event = new KdsOrderStatusChangedEvent(
                this, shopId, orderId, "ORD20261025002", KdsOrderStatus.COOKING, KdsOrderStatus.ALL_DONE);

        eventListener.onOrderStatusChanged(event);

        assertEquals(1, order.getNotice());
        verify(orderService).updateById(order);
        verify(dishMenuPushService).notifyMealPickupReady(eq(shopId), eq(orderId), eq("ORD20261025002"), any(), any(), eq("999"));
    }
}
