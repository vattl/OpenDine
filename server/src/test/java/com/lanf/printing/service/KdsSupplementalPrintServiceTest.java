package com.lanf.printing.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.printing.model.PrintScenario;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.Arrays;
import java.util.Collections;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsSupplementalPrintServiceTest {

    @AfterEach
    void cleanupTransactionState() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clearSynchronization();
        }
        TransactionSynchronizationManager.setActualTransactionActive(false);
    }

    @Test
    void submitsOnlyAfterCommitAndReloadsSelectedDetails() throws Exception {
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        PrintDispatcherService dispatcher = mock(PrintDispatcherService.class);
        KdsSupplementalPrintService service = new KdsSupplementalPrintService(
                orderService, detailService, deliveryService, dispatcher);

        Order order = new Order();
        order.setId(10);
        order.setShop_id(7);
        order.setDineInOrTakeOut("堂食");
        OrderDetail selected = new OrderDetail();
        selected.setId(21);
        OrderDetail other = new OrderDetail();
        other.setId(22);
        when(orderService.getById(10)).thenReturn(order);
        when(detailService.list(any(Wrapper.class))).thenReturn(Arrays.asList(selected, other));

        CountDownLatch dispatched = new CountDownLatch(2);
        doAnswer(invocation -> {
            dispatched.countDown();
            return Collections.emptyList();
        }).when(dispatcher).dispatch(anyInt(), anyString(), any());

        TransactionSynchronizationManager.setActualTransactionActive(true);
        TransactionSynchronizationManager.initSynchronization();
        try {
            service.scheduleAfterCommit(7, 10, Collections.singletonList(21), null);
            verify(dispatcher, never()).dispatch(anyInt(), anyString(), any());

            for (TransactionSynchronization synchronization
                    : TransactionSynchronizationManager.getSynchronizations()) {
                synchronization.afterCommit();
            }

            assertTrue(dispatched.await(2, TimeUnit.SECONDS));
            verify(dispatcher, times(2)).dispatch(anyInt(), anyString(), any());
            assertTrue(order.getGoods_list().size() == 1
                    && Integer.valueOf(21).equals(order.getGoods_list().get(0).getId()));
        } finally {
            service.close();
        }
    }

    @Test
    void packingOrderAddsIndependentPackingSlipAfterCommit() throws Exception {
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        PrintDispatcherService dispatcher = mock(PrintDispatcherService.class);
        KdsSupplementalPrintService service = new KdsSupplementalPrintService(
                orderService, detailService, deliveryService, dispatcher);

        Order order = new Order();
        order.setId(10);
        order.setShop_id(7);
        order.setDineInOrTakeOut("打包");
        OrderDetail detail = new OrderDetail();
        detail.setId(21);
        when(orderService.getById(10)).thenReturn(order);
        when(detailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(detail));

        CountDownLatch dispatched = new CountDownLatch(3);
        doAnswer(invocation -> {
            dispatched.countDown();
            return Collections.emptyList();
        }).when(dispatcher).dispatch(anyInt(), anyString(), any());

        try {
            service.scheduleAfterCommit(7, 10, Collections.singletonList(21), null);
            assertTrue(dispatched.await(2, TimeUnit.SECONDS));
            verify(dispatcher).dispatch(eq(7), eq(PrintScenario.PACKING), any());
        } finally {
            service.close();
        }
    }
}
