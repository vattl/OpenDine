package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.entity.R;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.service.ICategoryService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.service.PrintDispatcherService;
import com.lanf.printing.service.KdsSupplementalPrintService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderAutoAcceptPrintTest {

    @Test
    void failedPrintKeepsOrderAndDetailsPendingForRetry() {
        Fixture fixture = fixture(false);
        Order order = order();
        OrderDetail detail = detail(21);
        when(fixture.orderService.getById(order.getId())).thenReturn(order);
        when(fixture.orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(fixture.detailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(detail));

        R result = fixture.controller.autoAcceptAndPrint(order.getId());

        assertEquals(500, result.get("code"));
        assertEquals("mis_order", order.getOrder_receiving());
        assertEquals("mis_order", detail.getOrder_rece());
    }

    @Test
    void allPrintersFailedKeepsOrderAndDetailsPendingForRetry() {
        Fixture fixture = fixture(true);
        Order order = order();
        OrderDetail detail = detail(21);
        when(fixture.orderService.getById(order.getId())).thenReturn(order);
        when(fixture.orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(fixture.detailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(detail));
        when(fixture.dispatcher.dispatch(anyInt(), anyString(), any()))
                .thenReturn(Collections.singletonList(PrintDispatchResult.failed(101, "printer offline")));

        R result = fixture.controller.autoAcceptAndPrint(order.getId());

        assertEquals(500, result.get("code"));
        assertEquals("mis_order", order.getOrder_receiving());
        assertEquals("mis_order", detail.getOrder_rece());
    }

    @Test
    void targetedPrintOnlyAcceptsCurrentAddDishBatch() {
        Fixture fixture = fixture(true);
        Order order = order();
        OrderDetail previousFailed = detail(21);
        OrderDetail currentBatch = detail(22);
        List<OrderDetail> details = Arrays.asList(previousFailed, currentBatch);
        when(fixture.orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(fixture.detailService.list(any(Wrapper.class))).thenReturn(details);

        OrderController.PrintResult printResult = ReflectionTestUtils.invokeMethod(fixture.controller,
                "doAutoAcceptAndPrint", order, null, Collections.singletonList(22));

        assertTrue(printResult.success);
        assertEquals("mis_order", previousFailed.getOrder_rece());
        assertEquals("rec_order", currentBatch.getOrder_rece());
        assertEquals("mis_order", order.getOrder_receiving());
    }

    @Test
    void addDishBatchOnAcceptedOrderMaintainsRecOrder() {
        Fixture fixture = fixture(true);
        Order order = order();
        order.setOrder_receiving("rec_order");
        OrderDetail firstAccepted = detail(21);
        firstAccepted.setOrder_rece("rec_order");
        OrderDetail addedBatch = detail(22);
        List<OrderDetail> details = Arrays.asList(firstAccepted, addedBatch);
        when(fixture.orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(fixture.detailService.list(any(Wrapper.class))).thenReturn(details);

        OrderController.PrintResult printResult = ReflectionTestUtils.invokeMethod(fixture.controller,
                "doAutoAcceptAndPrint", order, null, Collections.singletonList(22));

        assertTrue(printResult.success);
        assertEquals("rec_order", firstAccepted.getOrder_rece());
        assertEquals("rec_order", addedBatch.getOrder_rece());
        assertEquals("rec_order", order.getOrder_receiving());
    }

    @Test
    void packingOrderDispatchesIndependentPackingSlip() {
        Fixture fixture = fixture(true);
        Order order = order();
        order.setDineInOrTakeOut("打包");
        OrderDetail detail = detail(21);
        when(fixture.orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(fixture.detailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(detail));

        OrderController.PrintResult result = ReflectionTestUtils.invokeMethod(fixture.controller,
                "doAutoAcceptAndPrint", order, null, null);

        assertTrue(result.success);
        verify(fixture.dispatcher).dispatch(eq(7), eq(PrintScenario.PACKING), any());
    }

    @Test
    void kdsEnabledAcceptsImmediatelyWithoutWaitingForSupplementalPrint() {
        Fixture fixture = fixture(true);
        Order order = order();
        OrderDetail detail = detail(21);
        when(fixture.orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(fixture.detailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(detail));
        when(fixture.kdsConfigService.isKdsEnabled(7)).thenReturn(true);

        OrderController.PrintResult result = ReflectionTestUtils.invokeMethod(fixture.controller,
                "doAutoAcceptAndPrint", order, null, null);

        assertTrue(result.success);
        assertEquals("rec_order", detail.getOrder_rece());
        assertEquals("rec_order", order.getOrder_receiving());
        verify(fixture.dispatcher, never()).dispatch(anyInt(), anyString(), any());
        verify(fixture.supplementalPrintService).scheduleAfterCommit(
                eq(7), eq(10), eq(Collections.singletonList(21)), isNull());
    }

    @Test
    void sideEffectRunsOnlyAfterTransactionCommit() {
        AtomicBoolean ran = new AtomicBoolean(false);
        TransactionSynchronizationManager.initSynchronization();
        try {
            OrderController.runAfterCommit(() -> ran.set(true));
            assertFalse(ran.get());

            for (TransactionSynchronization synchronization
                    : TransactionSynchronizationManager.getSynchronizations()) {
                synchronization.afterCommit();
            }
            assertTrue(ran.get());
        } finally {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    private static Fixture fixture(boolean printSuccess) {
        OrderController controller = new OrderController();
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        KdsConfigService kdsConfigService = mock(KdsConfigService.class);
        PrintDispatcherService dispatcher = mock(PrintDispatcherService.class);
        KdsSupplementalPrintService supplementalPrintService = mock(KdsSupplementalPrintService.class);
        ICategoryService categoryService = mock(ICategoryService.class);
        IShopService shopService = mock(IShopService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);

        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(detailService.updateById(any(OrderDetail.class))).thenReturn(true);
        when(kdsConfigService.shouldFeiePrint(anyInt())).thenReturn(true);
        when(categoryService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        Shop shop = new Shop();
        shop.setId(7);
        shop.setName("测试门店");
        when(shopService.getById(7)).thenReturn(shop);

        List<PrintDispatchResult> results = printSuccess
                ? Collections.singletonList(PrintDispatchResult.sent(101, 501))
                : Collections.singletonList(PrintDispatchResult.failed(101, "printer offline"));
        when(dispatcher.dispatch(anyInt(), anyString(), any())).thenReturn(results);

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        com.lanf.kds.delivery.CashierKdsProjectionService projections = mock(com.lanf.kds.delivery.CashierKdsProjectionService.class);
        when(projections.persistAcceptedOrder(anyInt(), any())).thenAnswer(call ->
                ((java.util.function.BooleanSupplier) call.getArgument(1)).getAsBoolean());
        ReflectionTestUtils.setField(controller, "cashierKdsProjectionService", projections);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "kdsConfigService", kdsConfigService);
        ReflectionTestUtils.setField(controller, "printDispatcherService", dispatcher);
        ReflectionTestUtils.setField(controller, "kdsSupplementalPrintService", supplementalPrintService);
        ReflectionTestUtils.setField(controller, "categoryService", categoryService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        return new Fixture(controller, orderService, detailService, kdsConfigService,
                dispatcher, supplementalPrintService);
    }

    private static Order order() {
        Order order = new Order();
        order.setId(10);
        order.setOrder_no("ORDER-10");
        order.setShop_id(7);
        order.setTable_number("A01");
        order.setDineInOrTakeOut("堂食");
        order.setOrder_receiving("mis_order");
        order.setOrderNumber(2);
        return order;
    }

    private static OrderDetail detail(int id) {
        OrderDetail detail = new OrderDetail();
        detail.setId(id);
        detail.setMId(10);
        detail.setName("测试菜品" + id);
        detail.setQuantity("1");
        detail.setCid("cid-1");
        detail.setOrder_rece("mis_order");
        return detail;
    }

    private static final class Fixture {
        final OrderController controller;
        final IOrderService orderService;
        final IOrderDetailService detailService;
        final KdsConfigService kdsConfigService;
        final PrintDispatcherService dispatcher;
        final KdsSupplementalPrintService supplementalPrintService;

        Fixture(OrderController controller, IOrderService orderService,
                IOrderDetailService detailService, KdsConfigService kdsConfigService,
                PrintDispatcherService dispatcher,
                KdsSupplementalPrintService supplementalPrintService) {
            this.controller = controller;
            this.orderService = orderService;
            this.detailService = detailService;
            this.kdsConfigService = kdsConfigService;
            this.dispatcher = dispatcher;
            this.supplementalPrintService = supplementalPrintService;
        }
    }
}
