package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsWorkflowServePrintTimingTest {

    private KdsWorkflowService service;
    private KdsTicketMapper ticketMapper;
    private IOrderDetailService orderDetailService;
    private IOrderService orderService;
    private KdsFlowBatchService flowBatchService;
    private KdsServePrintService servePrintService;

    @BeforeEach
    void setUp() {
        service = new KdsWorkflowService();
        ticketMapper = mock(KdsTicketMapper.class);
        orderDetailService = mock(IOrderDetailService.class);
        orderService = mock(IOrderService.class);
        flowBatchService = mock(KdsFlowBatchService.class);
        servePrintService = mock(KdsServePrintService.class);
        ReflectionTestUtils.setField(service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "flowBatchService", flowBatchService);
        ReflectionTestUtils.setField(service, "pushService", mock(KdsPushService.class));
        ReflectionTestUtils.setField(service, "servePrintService", servePrintService);

        OrderDetail detail = new OrderDetail();
        detail.setId(501);
        detail.setMId(1001);
        detail.setName("油边王");
        detail.setQuantity("2");
        when(orderDetailService.getById(501)).thenReturn(detail);
    }

    @Test
    void cookingCompletionDoesNotPrintBeforeServing() {
        KdsTicket before = ticket(2, 0, 0, 0);
        KdsTicket after = ticket(2, 1, 0, 0);
        when(ticketMapper.selectList(any(Wrapper.class)))
                .thenReturn(Collections.singletonList(before));
        when(flowBatchService.advanceCook(7, 91L, 1)).thenReturn(1);
        when(ticketMapper.selectById(91L)).thenReturn(after);

        service.advanceDetail(7, 501, KdsWorkflowQueue.PENDING_COOK, 1);

        verify(servePrintService, never()).printDetailLine(any(Integer.class), any(Integer.class), any(Integer.class));
    }

    @Test
    void servingCompletionPrintsTheActuallyServedQuantity() {
        KdsTicket before = ticket(2, 2, 0, 0);
        KdsTicket after = ticket(2, 2, 1, 0);
        when(ticketMapper.selectList(any(Wrapper.class)))
                .thenReturn(Collections.singletonList(before));
        when(flowBatchService.advanceServe(7, 91L, 1)).thenReturn(1);
        when(ticketMapper.selectById(91L)).thenReturn(after);

        service.advanceDetail(7, 501, KdsWorkflowQueue.READY_SERVE, 1);

        verify(servePrintService).printDetailLine(org.mockito.ArgumentMatchers.eq(7),
                org.mockito.ArgumentMatchers.eq(501), org.mockito.ArgumentMatchers.eq(1), anyLong());
    }

    @Test
    void completedItemCanStillBeRevokedToReadyServeAfterQuickUndoExpires() {
        KdsTicket completed = ticket(2, 2, 2, 1);
        KdsTicket revoked = ticket(2, 2, 1, 0);
        when(ticketMapper.selectList(any(Wrapper.class)))
                .thenReturn(Collections.singletonList(completed));
        when(flowBatchService.revokeServe(7, 91L, 1)).thenReturn(1);
        when(ticketMapper.selectById(91L)).thenReturn(revoked);

        Map<String, Object> result = service.revokeDetail(
                7, 501, KdsWorkflowQueue.DONE, 1);

        assertEquals(KdsWorkflowQueue.DONE, result.get("from_queue"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, result.get("to_queue"));
        assertEquals(1, result.get("advanced_quantity"));
        verify(flowBatchService).revokeServe(7, 91L, 1);
        ArgumentCaptor<UpdateWrapper<Order>> updateCaptor = ArgumentCaptor.forClass(UpdateWrapper.class);
        verify(orderService).update(updateCaptor.capture());
        assertTrue(updateCaptor.getValue().getSqlSet().contains("order_receiving"));
        assertTrue(updateCaptor.getValue().getSqlSet().contains("off_time"));
    }

    private static KdsTicket ticket(int prep, int cooked, int served, int archived) {
        KdsTicket ticket = new KdsTicket();
        ticket.setId(91L);
        ticket.setShop_id(7);
        ticket.setOrder_id(1001);
        ticket.setDetail_id(501);
        ticket.setItem_status(KdsItemStatus.DONE);
        ticket.setPrep_quantity(prep);
        ticket.setCooked_quantity(cooked);
        ticket.setServed_quantity(served);
        ticket.setArchived(archived);
        return ticket;
    }
}
