package com.lanf.kds.service;

import com.lanf.entity.Order;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsOrderHookAcceptanceGateTest {

    @Test
    void addDishesCallbackDoesNotRecordIntentAgainButStillCreatesTickets() {
        KdsOrderHook hook = new KdsOrderHook();
        IOrderService orders = mock(IOrderService.class);
        CashierKdsProjectionService projections = mock(CashierKdsProjectionService.class);
        KdsConfigService config = mock(KdsConfigService.class);
        KdsTicketService tickets = mock(KdsTicketService.class);
        Order order = order(101, "rec_order");
        when(orders.getById(101)).thenReturn(order);
        when(config.isKdsEnabled(1)).thenReturn(true);
        ReflectionTestUtils.setField(hook, "orderService", orders);
        ReflectionTestUtils.setField(hook, "cashierKdsProjectionService", projections);
        ReflectionTestUtils.setField(hook, "configService", config);
        ReflectionTestUtils.setField(hook, "ticketService", tickets);
        java.util.List<Integer> added = java.util.Collections.singletonList(123);
        hook.afterAddedDishesCommitted(order, added);
        org.mockito.Mockito.verifyNoInteractions(projections);
        verify(tickets).createTicketsForOrder(order, added, KdsOrderHook.Trigger.ADD_DISHES);
    }

    @Test
    void unacceptedOrderDoesNotRecordIntentOrCreateKitchenTickets() {
        KdsOrderHook hook = new KdsOrderHook();
        IOrderService orderService = mock(IOrderService.class);
        CashierKdsProjectionService projectionService = mock(CashierKdsProjectionService.class);
        Order order = order(101, "mis_order");
        when(orderService.getById(101)).thenReturn(order);
        ReflectionTestUtils.setField(hook, "orderService", orderService);
        ReflectionTestUtils.setField(hook, "cashierKdsProjectionService", projectionService);

        hook.afterOrderCommitted(order, null, KdsOrderHook.Trigger.CREATE);

        org.mockito.Mockito.verifyNoInteractions(projectionService);
    }

    @Test
    void intentPersistenceFailureIsNotSwallowedAsOptionalTicketFailure() {
        KdsOrderHook hook = new KdsOrderHook();
        IOrderService orders = mock(IOrderService.class);
        CashierKdsProjectionService projectionService = mock(CashierKdsProjectionService.class);
        Order order = order(101, "rec_order");
        when(orders.getById(101)).thenReturn(order);
        ReflectionTestUtils.setField(hook, "orderService", orders);
        ReflectionTestUtils.setField(hook, "cashierKdsProjectionService", projectionService);
        org.mockito.Mockito.doThrow(new IllegalStateException("database offline"))
                .when(projectionService).publishAfterCommit(101, "ORDER_ACCEPTED", null, null, null);
        org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException.class,
                () -> hook.afterOrderCommitted(order, null, KdsOrderHook.Trigger.CREATE));
    }

    @Test
    void acceptedOrderDoesNotSilentlyContinueWhenTicketCreationFails() {
        KdsOrderHook hook = new KdsOrderHook();
        IOrderService orders = mock(IOrderService.class);
        CashierKdsProjectionService projections = mock(CashierKdsProjectionService.class);
        KdsConfigService config = mock(KdsConfigService.class);
        KdsTicketService tickets = mock(KdsTicketService.class);
        Order order = order(101, "rec_order");
        when(orders.getById(101)).thenReturn(order);
        when(config.isKdsEnabled(1)).thenReturn(true);
        org.mockito.Mockito.doThrow(new IllegalStateException("ticket route unavailable"))
                .when(tickets).createTicketsForOrder(order, null, KdsOrderHook.Trigger.MANUAL);
        ReflectionTestUtils.setField(hook, "orderService", orders);
        ReflectionTestUtils.setField(hook, "cashierKdsProjectionService", projections);
        ReflectionTestUtils.setField(hook, "configService", config);
        ReflectionTestUtils.setField(hook, "ticketService", tickets);

        org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException.class,
                () -> hook.afterOrderCommitted(order, null, KdsOrderHook.Trigger.MANUAL));
    }

    private static Order order(int id, String receivingStatus) {
        Order order = new Order();
        order.setId(id);
        order.setShop_id(1);
        order.setOrder_no("ORD-" + id);
        order.setOrder_receiving(receivingStatus);
        return order;
    }
}
