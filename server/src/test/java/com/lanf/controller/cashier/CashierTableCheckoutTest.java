package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.CashierCheckoutService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierTableCheckoutTest {

    private CashierTableController controller;
    private ITableService tableService;
    private IOrderService orderService;
    private CashierCheckoutService checkoutService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new CashierTableController();
        tableService = mock(ITableService.class);
        orderService = mock(IOrderService.class);
        checkoutService = mock(CashierCheckoutService.class);
        request = new MockHttpServletRequest();

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 99);

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkoutService);
        ReflectionTestUtils.setField(controller, "request", request);
    }

    @Test
    void checkout_whenMultipleOrdersOnTable_shouldCheckoutAllAndCalculateChange() {
        Table table = new Table();
        table.setId(10);
        table.setShop_id(1);
        table.setNumber("A01");
        table.setStatus(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);

        Order o1 = new Order();
        o1.setId(1);
        o1.setOrder_no("O1");
        o1.setTable_number("A01");
        o1.setTransac_status("unsettled");
        o1.setSett_amount(30.0);

        Order o2 = new Order();
        o2.setId(2);
        o2.setOrder_no("O2");
        o2.setTable_number("A01");
        o2.setTransac_status("unsettled");
        o2.setSett_amount(20.0);

        when(orderService.list(any(Wrapper.class))).thenReturn(Arrays.asList(o1, o2));
        when(checkoutService.checkout(eq(1), any(Map.class))).thenReturn(R.ok("结账成功"));

        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "A01");
        body.put("paymentMethod", "cash");
        body.put("cashAmount", 100.0);

        R result = controller.checkout(body);

        assertEquals(0, result.get("code"));
        assertEquals("A01", result.get("tableNumber"));
        assertEquals(50.0, result.get("totalAmount"));
        assertEquals(100.0, result.get("cashAmount"));
        assertEquals(50.0, result.get("changeAmount"));
        assertEquals(Arrays.asList("O1", "O2"), result.get("settledOrders"));

        verify(checkoutService, times(2)).checkout(eq(1), any(Map.class));
        verify(checkoutService, times(2)).checkout(eq(1), org.mockito.Mockito.argThat(m -> Boolean.TRUE.equals(m.get("allowSlaveOrderCheckout"))));
    }

    @Test
    void checkout_whenNoUnsettledOrders_shouldReturnError() {
        Table table = new Table();
        table.setId(10);
        table.setShop_id(1);
        table.setNumber("A01");
        table.setStatus(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);

        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());

        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "A01");

        R result = controller.checkout(body);

        assertEquals(500, result.get("code"));
        assertEquals("该桌台暂无待结账订单", result.get("msg"));
    }

    @Test
    void checkout_whenInsufficientCash_shouldReturnError() {
        Table table = new Table();
        table.setId(10);
        table.setShop_id(1);
        table.setNumber("A01");
        table.setStatus(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);

        Order o1 = new Order();
        o1.setId(1);
        o1.setOrder_no("O1");
        o1.setTable_number("A01");
        o1.setTransac_status("unsettled");
        o1.setSett_amount(60.0);

        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(o1));

        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "A01");
        body.put("paymentMethod", "cash");
        body.put("cashAmount", 50.0);

        R result = controller.checkout(body);

        assertEquals(500, result.get("code"));
        assertTrue(result.get("msg").toString().contains("实收现金金额不足"));
    }
}
