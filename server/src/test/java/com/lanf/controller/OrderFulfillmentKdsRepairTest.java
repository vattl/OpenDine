package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderFulfillmentKdsRepairTest {

    @Test
    void retriesKdsTicketCreationForAcceptedOrderWithMissingTickets() {
        OrderController controller = new OrderController();
        IOrderService orders = mock(IOrderService.class);
        KdsConfigService config = mock(KdsConfigService.class);
        KdsOrderHook hook = mock(KdsOrderHook.class);
        Order order = acceptedOrder();
        when(orders.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));
        when(config.isKdsEnabled(7)).thenReturn(true);
        when(hook.hasMissingTicketsForOrder(order)).thenReturn(true);
        ReflectionTestUtils.setField(controller, "orderService", orders);
        ReflectionTestUtils.setField(controller, "kdsConfigService", config);
        ReflectionTestUtils.setField(controller, "kdsOrderHook", hook);

        controller.repairAcceptedKdsTickets();

        verify(hook).ensureTicketsForAcceptedOrder(order);
    }

    @Test
    void doesNotRetryWhenAnAcceptedOrderHasNoMissingTickets() {
        OrderController controller = new OrderController();
        IOrderService orders = mock(IOrderService.class);
        KdsConfigService config = mock(KdsConfigService.class);
        KdsOrderHook hook = mock(KdsOrderHook.class);
        Order order = acceptedOrder();
        when(orders.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));
        when(config.isKdsEnabled(7)).thenReturn(true);
        when(hook.hasMissingTicketsForOrder(order)).thenReturn(false);
        ReflectionTestUtils.setField(controller, "orderService", orders);
        ReflectionTestUtils.setField(controller, "kdsConfigService", config);
        ReflectionTestUtils.setField(controller, "kdsOrderHook", hook);

        controller.repairAcceptedKdsTickets();

        verify(hook, never()).ensureTicketsForAcceptedOrder(any(Order.class));
    }

    private static Order acceptedOrder() {
        Order order = new Order();
        order.setId(10);
        order.setShop_id(7);
        order.setOrder_no("ORDER-10");
        order.setOrder_receiving("rec_order");
        return order;
    }
}
