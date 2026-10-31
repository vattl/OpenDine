package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class KdsWorkflowAdvanceIdempotencyTest {

    private KdsWorkflowService workflowService;
    private KdsTicketMapper ticketMapper;
    private IOrderDetailService orderDetailService;
    private IOrderService orderService;

    @BeforeEach
    void setUp() {
        workflowService = new KdsWorkflowService();
        ticketMapper = mock(KdsTicketMapper.class);
        orderDetailService = mock(IOrderDetailService.class);
        orderService = mock(IOrderService.class);

        ReflectionTestUtils.setField(workflowService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(workflowService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(workflowService, "orderService", orderService);
    }

    @Test
    @DisplayName("KdsTicketQuantityUtil.isPastQueue 与 resolveCurrentQueue 状态判定正确")
    void testTicketQuantityUtilQueueResolution() {
        // 场景 1: 工单制作完成待传菜 (prep=2, cook=2, served=0 -> 在 ready_serve)
        // 制作完成后在待传菜中不属于已出餐，item_status=COOKING，archived=0
        KdsTicket readyTicket = new KdsTicket();
        readyTicket.setItem_status(KdsItemStatus.COOKING);
        readyTicket.setArchived(0);
        readyTicket.setPrep_quantity(2);
        readyTicket.setCooked_quantity(2);
        readyTicket.setServed_quantity(0);

        assertTrue(KdsTicketQuantityUtil.isPastQueue(readyTicket, 2, KdsWorkflowQueue.PENDING_PREP));
        assertTrue(KdsTicketQuantityUtil.isPastQueue(readyTicket, 2, KdsWorkflowQueue.PENDING_COOK));
        assertFalse(KdsTicketQuantityUtil.isPastQueue(readyTicket, 2, KdsWorkflowQueue.READY_SERVE));
        assertFalse(KdsTicketQuantityUtil.isPastQueue(readyTicket, 2, KdsWorkflowQueue.DONE));
        assertEquals(KdsWorkflowQueue.READY_SERVE, KdsTicketQuantityUtil.resolveCurrentQueue(readyTicket, 2));

        // 场景 2: 工单已送达 (prep=2, cook=2, served=2 -> 在 done)
        KdsTicket doneTicket = new KdsTicket();
        doneTicket.setItem_status(KdsItemStatus.DONE);
        doneTicket.setArchived(1);
        doneTicket.setPrep_quantity(2);
        doneTicket.setCooked_quantity(2);
        doneTicket.setServed_quantity(2);

        assertTrue(KdsTicketQuantityUtil.isPastQueue(doneTicket, 2, KdsWorkflowQueue.PENDING_PREP));
        assertTrue(KdsTicketQuantityUtil.isPastQueue(doneTicket, 2, KdsWorkflowQueue.PENDING_COOK));
        assertTrue(KdsTicketQuantityUtil.isPastQueue(doneTicket, 2, KdsWorkflowQueue.READY_SERVE));
        assertFalse(KdsTicketQuantityUtil.isPastQueue(doneTicket, 2, KdsWorkflowQueue.DONE));
        assertEquals(KdsWorkflowQueue.DONE, KdsTicketQuantityUtil.resolveCurrentQueue(doneTicket, 2));

        // 场景 3: 工单在 pending_cook (prep=2, cook=0, served=0)
        KdsTicket cookTicket = new KdsTicket();
        cookTicket.setItem_status(KdsItemStatus.PENDING);
        cookTicket.setArchived(0);
        cookTicket.setPrep_quantity(2);
        cookTicket.setCooked_quantity(0);
        cookTicket.setServed_quantity(0);

        assertTrue(KdsTicketQuantityUtil.isPastQueue(cookTicket, 2, KdsWorkflowQueue.PENDING_PREP));
        assertFalse(KdsTicketQuantityUtil.isPastQueue(cookTicket, 2, KdsWorkflowQueue.PENDING_COOK));
        assertFalse(KdsTicketQuantityUtil.isPastQueue(cookTicket, 2, KdsWorkflowQueue.READY_SERVE));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsTicketQuantityUtil.resolveCurrentQueue(cookTicket, 2));

        // 场景 4: 作废工单
        KdsTicket voidTicket = new KdsTicket();
        voidTicket.setItem_status(KdsItemStatus.VOID);
        assertFalse(KdsTicketQuantityUtil.isPastQueue(voidTicket, 2, KdsWorkflowQueue.PENDING_COOK));
        assertEquals(KdsWorkflowQueue.DONE, KdsTicketQuantityUtil.resolveCurrentQueue(voidTicket, 2));
    }

    @Test
    @DisplayName("advanceDetail 遇到工单已越过该阶段时自愈并返回成功，不抛 OptimisticLockException")
    void testAdvanceDetailIdempotentWhenAlreadyPassedQueue() {
        int shopId = 1;
        int detailId = 56561;
        int orderId = 13720;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(orderId);
        detail.setQuantity("1");
        detail.setLine_status("normal");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        // 工单实际状态：已制作完成，在 ready_serve (cooked=1, served=0)
        KdsTicket ticket = new KdsTicket();
        ticket.setId(9476L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(detailId);
        ticket.setPrep_quantity(1);
        ticket.setCooked_quantity(1);
        ticket.setServed_quantity(0);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setArchived(0);
        ticket.setCreated_at(new Date());
        ticket.setUpdated_at(new Date());

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));

        // 尝试从 pending_cook 再次推进该明细（模拟用户重复点击或网络重试）
        Map<String, Object> result = workflowService.advanceDetail(shopId, detailId, KdsWorkflowQueue.PENDING_COOK, 1);

        assertNotNull(result);
        assertEquals(detailId, result.get("detail_id"));
        assertEquals(orderId, result.get("order_id"));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, result.get("from_queue"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, result.get("to_queue"));
        assertEquals(1, result.get("requested_quantity"));
        assertEquals(0, result.get("advanced_quantity"));
    }

    @Test
    @DisplayName("advanceDetail 遇到工单未越过该阶段且不在当前队列时，严格抛出 OptimisticLockException")
    void testAdvanceDetailThrowsWhenNotPassedAndNotInQueue() {
        int shopId = 1;
        int detailId = 56562;
        int orderId = 13720;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(orderId);
        detail.setQuantity("1");
        detail.setLine_status("normal");
        detail.setOrder_rece("rec_order");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        // 工单实际状态：在 pending_cook (prep=1, cooked=0, served=0)
        KdsTicket ticket = new KdsTicket();
        ticket.setId(9477L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(detailId);
        ticket.setPrep_quantity(1);
        ticket.setCooked_quantity(0);
        ticket.setServed_quantity(0);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setArchived(0);

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));

        // 试图从 ready_serve 推进（越级非法操作）
        assertThrows(KdsWorkflowService.OptimisticLockException.class, () -> {
            workflowService.advanceDetail(shopId, detailId, KdsWorkflowQueue.READY_SERVE, 1);
        });
    }

    @Test
    @DisplayName("advanceOrder 在订单已无当前队列待推进明细时幂等成功，不抛 IllegalArgumentException")
    void testAdvanceOrderIdempotentWhenNoRemainingItems() {
        int shopId = 1;
        int orderId = 13720;

        Order order = new Order();
        order.setId(orderId);
        order.setShop_id(shopId);
        when(orderService.getById(orderId)).thenReturn(order);

        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = workflowService.advanceOrder(shopId, orderId, KdsWorkflowQueue.PENDING_COOK);

        assertNotNull(result);
        assertEquals(orderId, result.get("order_id"));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, result.get("from_queue"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, result.get("to_queue"));
        assertEquals(0, result.get("updated"));
        assertEquals(0, result.get("advanced_quantity"));
    }
}
