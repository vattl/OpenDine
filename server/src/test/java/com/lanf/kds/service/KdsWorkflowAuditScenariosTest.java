package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class KdsWorkflowAuditScenariosTest {

    private KdsWorkflowService workflowService;
    private KdsExpeditionServeService expeditionServeService;
    private KdsWorkflowHoldService holdService;

    private KdsTicketMapper ticketMapper;
    private IOrderDetailService orderDetailService;
    private IOrderService orderService;
    private KdsFlowBatchService flowBatchService;
    private CashierKdsProjectionService projectionService;
    private KdsPushService pushService;
    private KdsServePrintService servePrintService;

    @BeforeEach
    void setUp() {
        workflowService = new KdsWorkflowService();
        expeditionServeService = new KdsExpeditionServeService();

        ticketMapper = mock(KdsTicketMapper.class);
        orderDetailService = mock(IOrderDetailService.class);
        orderService = mock(IOrderService.class);
        flowBatchService = mock(KdsFlowBatchService.class);
        projectionService = mock(CashierKdsProjectionService.class);
        pushService = mock(KdsPushService.class);
        servePrintService = mock(KdsServePrintService.class);

        holdService = new KdsWorkflowHoldService();
        ReflectionTestUtils.setField(holdService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(holdService, "orderService", orderService);
        ReflectionTestUtils.setField(holdService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(holdService, "pushService", pushService);

        ReflectionTestUtils.setField(workflowService, "holdService", holdService);
        ReflectionTestUtils.setField(workflowService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(workflowService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(workflowService, "orderService", orderService);
        ReflectionTestUtils.setField(workflowService, "flowBatchService", flowBatchService);
        ReflectionTestUtils.setField(workflowService, "projectionService", projectionService);
        ReflectionTestUtils.setField(workflowService, "pushService", pushService);
        ReflectionTestUtils.setField(workflowService, "servePrintService", servePrintService);

        ReflectionTestUtils.setField(expeditionServeService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(expeditionServeService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(expeditionServeService, "orderService", orderService);
        ReflectionTestUtils.setField(expeditionServeService, "flowBatchService", flowBatchService);
        ReflectionTestUtils.setField(expeditionServeService, "projectionService", projectionService);
        ReflectionTestUtils.setField(expeditionServeService, "pushService", pushService);
        ReflectionTestUtils.setField(expeditionServeService, "servePrintService", servePrintService);
    }

    @Test
    @DisplayName("场景 1: 等叫(mis_order)菜品在 advanceDetail 时被严格拦截，抛出业务异常")
    void testAdvanceDetail_HeldDish_ThrowsException() {
        int shopId = 1;
        int detailId = 1001;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setQuantity("1");
        detail.setOrder_rece("mis_order"); // 等叫
        detail.setLine_status("normal");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(5001L);
        ticket.setShop_id(shopId);
        ticket.setDetail_id(detailId);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setArchived(0);
        ticket.setPrep_quantity(1);
        ticket.setCooked_quantity(0);
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> {
            workflowService.advanceDetail(shopId, detailId, KdsWorkflowQueue.PENDING_COOK, 1);
        });
        assertTrue(ex.getMessage().contains("菜品处于等叫状态"));
    }

    @Test
    @DisplayName("场景 2: 整单推进(advanceOrder)遇到等叫菜品时安全跳过，不阻断正常菜品推进")
    void testAdvanceOrder_SkipsHeldDishes() {
        int shopId = 1;
        int orderId = 888;
        int normalDetailId = 2001;
        int heldDetailId = 2002;

        OrderDetail normalDetail = new OrderDetail();
        normalDetail.setId(normalDetailId);
        normalDetail.setMId(orderId);
        normalDetail.setQuantity("1");
        normalDetail.setOrder_rece("rec_order");
        normalDetail.setLine_status("normal");

        OrderDetail heldDetail = new OrderDetail();
        heldDetail.setId(heldDetailId);
        heldDetail.setMId(orderId);
        heldDetail.setQuantity("1");
        heldDetail.setOrder_rece("mis_order"); // 等叫
        heldDetail.setLine_status("normal");

        when(orderDetailService.getById(normalDetailId)).thenReturn(normalDetail);
        when(orderDetailService.getById(heldDetailId)).thenReturn(heldDetail);

        KdsTicket normalTicket = new KdsTicket();
        normalTicket.setId(6001L);
        normalTicket.setShop_id(shopId);
        normalTicket.setOrder_id(orderId);
        normalTicket.setDetail_id(normalDetailId);
        normalTicket.setPrep_quantity(1);
        normalTicket.setCooked_quantity(0);
        normalTicket.setServed_quantity(0);
        normalTicket.setItem_status(KdsItemStatus.PENDING);
        normalTicket.setArchived(0);

        KdsTicket heldTicket = new KdsTicket();
        heldTicket.setId(6002L);
        heldTicket.setShop_id(shopId);
        heldTicket.setOrder_id(orderId);
        heldTicket.setDetail_id(heldDetailId);
        heldTicket.setPrep_quantity(1);
        heldTicket.setCooked_quantity(0);
        heldTicket.setServed_quantity(0);
        heldTicket.setItem_status(KdsItemStatus.PENDING);
        heldTicket.setArchived(0);

        // ticketsForOrderQueue
        when(ticketMapper.selectList(any())).thenReturn(Arrays.asList(normalTicket, heldTicket));
        when(ticketMapper.selectById(6001L)).thenReturn(normalTicket);

        // advanceCook
        when(flowBatchService.advanceCook(eq(shopId), eq(6001L), eq(1))).thenReturn(1);

        Map<String, Object> result = workflowService.advanceOrder(shopId, orderId, KdsWorkflowQueue.PENDING_COOK);

        assertNotNull(result);
        assertEquals(1, result.get("updated"), "正常菜品应被推进");
        assertEquals(1, result.get("skipped"), "等叫菜品应被安全跳过");
        assertEquals(1, result.get("advanced_quantity"));
        verify(flowBatchService, times(1)).advanceCook(eq(shopId), eq(6001L), eq(1));
        verify(flowBatchService, never()).advanceCook(eq(shopId), eq(6002L), anyInt());
    }

    @Test
    @DisplayName("场景 3: 出餐屏(serveByDish)按菜品批量划单时，调用 flowBatchService 批次推进并同步多看板与收银投影")
    void testExpeditionServeByDish_SyncsFlowBatchAndProjection() {
        int shopId = 1;
        int orderId = 999;
        int detailId = 3001;
        String dishName = "烤羊肉串";

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(orderId);
        detail.setName(dishName);
        detail.setQuantity("5");
        detail.setOrder_rece("rec_order");
        detail.setLine_status("normal");

        KdsTicket ticket = new KdsTicket();
        ticket.setId(7001L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(detailId);
        ticket.setPrep_quantity(5);
        ticket.setCooked_quantity(5);
        ticket.setServed_quantity(0);
        ticket.setScreen_tag("grill");
        ticket.setItem_status(KdsItemStatus.DONE);
        ticket.setArchived(0);
        ticket.setDone_at(new Date());

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderDetailService.listByIds(any())).thenReturn(Collections.singletonList(detail));
        when(orderDetailService.getById(detailId)).thenReturn(detail);
        when(ticketMapper.selectById(7001L)).thenReturn(ticket);

        when(flowBatchService.advanceServe(eq(shopId), eq(7001L), eq(3))).thenAnswer(inv -> {
            ticket.setServed_quantity(3);
            return 3;
        });

        Map<String, Object> result = expeditionServeService.serveByDish(shopId, dishName, 3, "grill");

        assertNotNull(result);
        assertEquals(3, result.get("served"));
        assertEquals(1, result.get("updated_lines"));

        // 验证调用了 flowBatchService.advanceServe，而不是仅直接修改 ticket
        verify(flowBatchService, times(1)).advanceServe(eq(shopId), eq(7001L), eq(3));

        // 验证向 WORKFLOW_BOARD 发送了 WebSocket 广播
        verify(pushService, atLeastOnce()).updateOrder(eq(shopId), eq(KdsScreenTag.WORKFLOW_BOARD), any());

        // 验证向收银端推送了明细状态下行
        verify(projectionService, times(1)).publishLineStatus(eq(shopId), eq(orderId), any());
    }

    @Test
    @DisplayName("场景 4: 已完成工单回撤(revokeDetail from done)解除订单 off_order 状态并同步收银投影")
    void testRevokeDetail_FromDone_ReopensOrderAndPublishesProjection() {
        int shopId = 1;
        int orderId = 1234;
        int detailId = 4001;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(orderId);
        detail.setQuantity("2");
        detail.setOrder_rece("rec_order");
        detail.setLine_status("normal");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(8001L);
        ticket.setShop_id(shopId);
        ticket.setOrder_id(orderId);
        ticket.setDetail_id(detailId);
        ticket.setPrep_quantity(2);
        ticket.setCooked_quantity(2);
        ticket.setServed_quantity(2);
        ticket.setItem_status(KdsItemStatus.DONE);
        ticket.setArchived(1);

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(ticketMapper.selectById(8001L)).thenReturn(ticket);
        when(flowBatchService.revokeServe(eq(shopId), eq(8001L), eq(1))).thenAnswer(inv -> {
            ticket.setServed_quantity(1);
            ticket.setArchived(0);
            return 1;
        });

        Map<String, Object> result = workflowService.revokeDetail(shopId, detailId, KdsWorkflowQueue.DONE, 1);

        assertNotNull(result);
        assertEquals(KdsWorkflowQueue.DONE, result.get("from_queue"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, result.get("to_queue"));
        assertEquals(1, result.get("advanced_quantity")); // revoked count

        // 验证调用了 reopenOrderAfterCompletedRevoke（对 orderService 执行 update 恢复 rec_order）
        verify(orderService, times(1)).update(any(UpdateWrapper.class));

        // 验证同步向收银端下发了 LineStatus 变化
        verify(projectionService, times(1)).publishLineStatus(eq(shopId), eq(orderId), any());
    }

    @Test
    @DisplayName("场景 6: 等叫操作严格校验门店归属，跨店明细直接抛出越权异常")
    void testHold_CrossShopAccess_ThrowsSecurityException() {
        int deviceShopId = 1;
        int detailId = 9001;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(888);
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        Order order = new Order();
        order.setId(888);
        order.setShop_id(2); // 属于分店 2
        when(orderService.getById(888)).thenReturn(order);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> {
            holdService.hold(deviceShopId, detailId);
        });
        assertTrue(ex.getMessage().contains("无权操作其他门店"));
    }

    @Test
    @DisplayName("场景 7: 已退菜品尝试等叫时被严格拦截")
    void testHold_AlreadyRefunded_ThrowsException() {
        int shopId = 1;
        int detailId = 9002;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(889);
        detail.setLine_status("refunded");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        Order order = new Order();
        order.setId(889);
        order.setShop_id(shopId);
        when(orderService.getById(889)).thenReturn(order);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> {
            holdService.hold(shopId, detailId);
        });
        assertTrue(ex.getMessage().contains("已退菜品无法设为等叫"));
    }

    @Test
    @DisplayName("场景 8: 已全部出餐完成的菜品无法再设为等叫")
    void testHold_AlreadyCompleted_ThrowsException() {
        int shopId = 1;
        int detailId = 9003;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(890);
        detail.setQuantity("2");
        detail.setLine_status("normal");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        Order order = new Order();
        order.setId(890);
        order.setShop_id(shopId);
        when(orderService.getById(890)).thenReturn(order);

        KdsTicket ticket = new KdsTicket();
        ticket.setDetail_id(detailId);
        ticket.setItem_status(KdsItemStatus.DONE);
        ticket.setServed_quantity(2);
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> {
            holdService.hold(shopId, detailId);
        });
        assertTrue(ex.getMessage().contains("无法设为等叫"));
    }

    @Test
    @DisplayName("场景 9: 正常菜品等叫与起菜状态流转并下发 WS 通知")
    void testHoldAndRelease_Success() {
        int shopId = 1;
        int detailId = 9004;

        OrderDetail detail = new OrderDetail();
        detail.setId(detailId);
        detail.setMId(891);
        detail.setQuantity("1");
        detail.setLine_status("normal");
        when(orderDetailService.getById(detailId)).thenReturn(detail);

        Order order = new Order();
        order.setId(891);
        order.setShop_id(shopId);
        when(orderService.getById(891)).thenReturn(order);

        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());

        // 执行等叫
        Map<String, Object> holdRes = holdService.hold(shopId, detailId);
        assertEquals(1, holdRes.get("hold_flag"));
        assertEquals("mis_order", detail.getOrder_rece());
        verify(orderDetailService, atLeastOnce()).updateById(detail);
        verify(pushService, times(1)).dishFlagsChanged(eq(shopId), any());

        // 执行起菜
        Map<String, Object> releaseRes = holdService.release(shopId, detailId);
        assertEquals(0, releaseRes.get("hold_flag"));
        assertEquals("rec_order", detail.getOrder_rece());
        verify(orderDetailService, atLeast(2)).updateById(detail);
        verify(pushService, times(2)).dishFlagsChanged(eq(shopId), any());
    }
}
