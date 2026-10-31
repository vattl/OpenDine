package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.stubbing.Answer;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class OrderControllerTableInfoTest {

    private OrderController controller;
    private ITableService tableService;
    private IOrderService orderService;
    private com.lanf.service.IShopService shopService;

    @BeforeEach
    void setUp() {
        controller = new OrderController();
        tableService = mock(ITableService.class);
        orderService = mock(IOrderService.class);
        shopService = mock(com.lanf.service.IShopService.class);

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
    }

    @Test
    void getTableInfo_whenMergedTableHasMultipleUsersOrders_shouldReturnCurrentUserOrder() {
        Table table = new Table();
        table.setId(2);
        table.setShop_id(1);
        table.setNumber("A02");
        table.setStatus(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);

        Order orderA = new Order();
        orderA.setId(101);
        orderA.setOrder_no("ORD-A");
        orderA.setTable_number("A02");
        orderA.setOpenid("user_A");
        orderA.setTransac_status("unsettled");
        orderA.setOrder_time(new Date(1000000L));
        orderA.setSett_amount(50.0);

        Order orderB = new Order();
        orderB.setId(102);
        orderB.setOrder_no("ORD-B");
        orderB.setTable_number("A02");
        orderB.setOpenid("user_B");
        orderB.setTransac_status("unsettled");
        orderB.setOrder_time(new Date(2000000L));
        orderB.setSett_amount(80.0);

        when(orderService.getOne(any(Wrapper.class))).thenAnswer((Answer<Order>) invocation -> {
            Object arg = invocation.getArgument(0);
            if (arg instanceof com.baomidou.mybatisplus.core.conditions.query.QueryWrapper) {
                com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<?> wrapper = (com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<?>) arg;
                wrapper.getSqlSegment();
                Map<String, Object> paramNameValuePairs = wrapper.getParamNameValuePairs();
                if (paramNameValuePairs != null) {
                    for (Object val : paramNameValuePairs.values()) {
                        if ("user_A".equals(val)) return orderA;
                        if ("user_B".equals(val)) return orderB;
                    }
                }
            }
            return null;
        });

        // Customer A requests table info for A02
        MockHttpServletRequest requestA = new MockHttpServletRequest();
        requestA.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_A");
        requestA.addHeader("X-Shop-Id", "1");

        R resultA = controller.getTableInfo("A02", requestA);
        assertEquals(0, resultA.get("code"));
        assertEquals("ORD-A", resultA.get("orderNo"));

        // Customer B requests table info for A02
        MockHttpServletRequest requestB = new MockHttpServletRequest();
        requestB.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_B");
        requestB.addHeader("X-Shop-Id", "1");

        R resultB = controller.getTableInfo("A02", requestB);
        assertEquals(0, resultB.get("code"));
        assertEquals("ORD-B", resultB.get("orderNo"));
    }

    @Test
    void getTableInfo_whenStrangerAccessesTable_shouldReturn403() {
        Table table = new Table();
        table.setId(2);
        table.setShop_id(1);
        table.setNumber("A02");
        table.setStatus(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);

        // Stranger has no order on A02
        when(orderService.getOne(any(Wrapper.class))).thenReturn(null);
        // But other orders exist on table A02
        when(orderService.count(any(Wrapper.class))).thenReturn(2);

        MockHttpServletRequest requestStranger = new MockHttpServletRequest();
        requestStranger.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "stranger_openid");
        requestStranger.addHeader("X-Shop-Id", "1");

        R result = controller.getTableInfo("A02", requestStranger);
        assertEquals(403, result.get("code"));
        assertEquals("无权查看该桌订单", result.get("msg"));
    }

    @Test
    void getTableInfo_whenTableHasNoOrdersAtAll_shouldReturnNotFoundError() {
        Table table = new Table();
        table.setId(3);
        table.setShop_id(1);
        table.setNumber("A03");
        table.setStatus(0);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);

        when(orderService.getOne(any(Wrapper.class))).thenReturn(null);
        when(orderService.count(any(Wrapper.class))).thenReturn(0);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_A");
        request.addHeader("X-Shop-Id", "1");

        R result = controller.getTableInfo("A03", request);
        assertEquals(500, result.get("code"));
        assertEquals("未找到该台号的订单信息", result.get("msg"));
    }

    @Test
    void getTableInfo_whenTableDoesNotExist_shouldReturnError() {
        when(tableService.getOne(any(Wrapper.class))).thenReturn(null);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_A");
        request.addHeader("X-Shop-Id", "1");

        R result = controller.getTableInfo("UNKNOWN", request);
        assertEquals(500, result.get("code"));
        assertEquals("台号不存在", result.get("msg"));
    }
}
