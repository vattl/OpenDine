package com.lanf.kds.delivery;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.controller.OrderController;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.service.PrintDispatcherService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class CashierKdsAcceptanceDecouplingTest {

    @Test
    @DisplayName("KDS启用时，物理打印失败不应阻断自动接单与 rec_order 状态更新")
    void autoAcceptSucceedsWhenKdsEnabledEvenIfPrintFails() {
        OrderController controller = new OrderController();

        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService orderDetailService = mock(IOrderDetailService.class);
        KdsConfigService kdsConfigService = mock(KdsConfigService.class);
        PrintDispatcherService printDispatcherService = mock(PrintDispatcherService.class);
        ITakeoutDeliveryService takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        CashierKdsProjectionService projectionService = mock(CashierKdsProjectionService.class);

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(controller, "kdsConfigService", kdsConfigService);
        ReflectionTestUtils.setField(controller, "printDispatcherService", printDispatcherService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(controller, "cashierKdsProjectionService", projectionService);

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD-101");
        order.setShop_id(1);
        order.setDineInOrTakeOut("堂食");
        order.setOrder_receiving("mis_order");

        OrderDetail detail = new OrderDetail();
        detail.setId(1001);
        detail.setMId(101);
        detail.setOrder_rece("mis_order");

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderDetailService.list(any(QueryWrapper.class)))
                .thenReturn(Collections.singletonList(detail))
                .thenReturn(Collections.singletonList(detail));
        when(orderDetailService.updateById(any(OrderDetail.class))).thenReturn(true);
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(kdsConfigService.shouldFeiePrint(1)).thenReturn(true);
        when(kdsConfigService.isKdsEnabled(1)).thenReturn(true);

        // 模拟打印机调度返回失败结果
        PrintDispatchResult failResult = PrintDispatchResult.failed(1L, "err");
        when(printDispatcherService.dispatch(eq(1), any(), any()))
                .thenReturn(Collections.singletonList(failResult));

        when(projectionService.persistAcceptedOrder(eq(101), any())).thenAnswer(invocation -> {
            java.util.function.BooleanSupplier supplier = invocation.getArgument(1);
            return supplier.getAsBoolean();
        });

        // 执行 doAutoAcceptAndPrint
        Object result = ReflectionTestUtils.invokeMethod(controller, "doAutoAcceptAndPrint", order);
        assertNotNull(result);
        Boolean success = (Boolean) ReflectionTestUtils.getField(result, "success");
        assertTrue(success, "KDS 启用时，即使打印失败，自动接单应成功以放行 KDS 投影与工单");
        assertEquals("rec_order", order.getOrder_receiving(), "订单接单状态应更新为 rec_order");
    }

    @Test
    @DisplayName("管理端手动接单时，应同步更新未接单明细 order_rece 为 rec_order")
    void adminReceivingSynchronizesOrderDetailStatus() {
        AdminOrderController controller = new AdminOrderController();

        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService orderDetailService = mock(IOrderDetailService.class);
        KdsOrderHook kdsOrderHook = mock(KdsOrderHook.class);

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(controller, "kdsOrderHook", kdsOrderHook);

        Order existingOrder = new Order();
        existingOrder.setId(201);
        existingOrder.setOrder_no("ORD-201");
        existingOrder.setShop_id(1);
        existingOrder.setOrder_receiving("mis_order");

        when(orderService.getById(201)).thenReturn(existingOrder);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        OrderDetail detail1 = new OrderDetail();
        detail1.setId(2001);
        detail1.setMId(201);
        detail1.setOrder_rece("mis_order");

        OrderDetail detail2 = new OrderDetail();
        detail2.setId(2002);
        detail2.setMId(201);
        detail2.setOrder_rece("rec_order");

        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(detail1, detail2));
        when(orderDetailService.updateById(any(OrderDetail.class))).thenReturn(true);

        Order req = new Order();
        req.setId(201);
        req.setOrder_receiving("rec_order");

        com.lanf.entity.R r = controller.receiving(req);
        assertEquals(0, r.get("code"));
        assertEquals("rec_order", detail1.getOrder_rece(), "未接单明细应同步更新为 rec_order");
        verify(kdsOrderHook, times(1)).afterOrderCommitted(eq(existingOrder), isNull(), eq(KdsOrderHook.Trigger.MANUAL));
    }
}
