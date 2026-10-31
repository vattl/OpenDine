package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOrderLogService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class CashierOrderHangWorkflowTest {

    private CashierOrderController controller;
    private IOrderService orderService;
    private IOrderLogService orderLogService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new CashierOrderController();
        orderService = mock(IOrderService.class);
        orderLogService = mock(IOrderLogService.class);
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 108);

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "request", request);
    }

    @Test
    @DisplayName("场景 1: 正常未结订单挂单成功，记录状态、时间、原因和操作员")
    void testHangOrder_Success() {
        String orderNo = "ORD20261019001";
        Order order = new Order();
        order.setId(101);
        order.setOrder_no(orderNo);
        order.setShop_id(2);
        order.setTransac_status("unsettled");
        order.setHang_status(0);

        when(orderService.getOne(any(), eq(false))).thenReturn(order);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", orderNo);
        body.put("reason", "顾客忘带手机回去取");

        R r = controller.hang(body);
        assertEquals(0, r.get("code"));
        assertEquals(orderNo, r.get("order_no"));
        assertEquals(1, r.get("hang_status"));

        ArgumentCaptor<Order> captor = ArgumentCaptor.forClass(Order.class);
        verify(orderService).updateById(captor.capture());
        Order saved = captor.getValue();
        assertEquals(1, saved.getHang_status());
        assertNotNull(saved.getHang_time());
        assertEquals("顾客忘带手机回去取", saved.getHang_reason());
        assertEquals(108, saved.getHang_admin_id());
    }

    @Test
    @DisplayName("场景 2: 已结账或已取消订单禁止挂单")
    void testHangOrder_AlreadyPaid_Rejected() {
        String orderNo = "ORD20261019002";
        Order order = new Order();
        order.setId(102);
        order.setOrder_no(orderNo);
        order.setShop_id(2);
        order.setTransac_status("success"); // 已结账

        when(orderService.getOne(any(), eq(false))).thenReturn(order);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", orderNo);

        R r = controller.hang(body);
        assertNotEquals(0, r.get("code"));
        assertTrue(r.get("msg").toString().contains("已结账或已取消"));
        verify(orderService, never()).updateById(any());
    }

    @Test
    @DisplayName("场景 3: 跨店订单挂单被严格拦截")
    void testHangOrder_CrossShop_Rejected() {
        String orderNo = "ORD20261019003";
        // 模拟当前门店为 shop 2，查出的订单不存在于 shop 2
        when(orderService.getOne(any(), eq(false))).thenReturn(null);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", orderNo);

        R r = controller.hang(body);
        assertNotEquals(0, r.get("code"));
        assertTrue(r.get("msg").toString().contains("订单不存在或不属于当前门店"));
        verify(orderService, never()).updateById(any());
    }

    @Test
    @DisplayName("场景 4: 取单成功，清除挂单状态并更新订单")
    void testUnhangOrder_Success() {
        String orderNo = "ORD20261019004";
        Order order = new Order();
        order.setId(104);
        order.setOrder_no(orderNo);
        order.setShop_id(2);
        order.setTransac_status("unsettled");
        order.setHang_status(1);
        order.setHang_time(new Date());
        order.setHang_reason("排队等待");

        when(orderService.getOne(any(), eq(false))).thenReturn(order);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", orderNo);

        R r = controller.unhang(body);
        assertEquals(0, r.get("code"));
        assertEquals(0, r.get("hang_status"));

        ArgumentCaptor<Order> captor = ArgumentCaptor.forClass(Order.class);
        verify(orderService).updateById(captor.capture());
        Order saved = captor.getValue();
        assertEquals(0, saved.getHang_status());
        assertNull(saved.getHang_time());
        assertNull(saved.getHang_reason());
    }

    @Test
    @DisplayName("场景 5: 查询当前门店挂单列表，按门店过滤且按挂单时间升序")
    void testHangList_FiltersByShop() {
        Order o1 = new Order();
        o1.setId(201);
        o1.setOrder_no("ORD-A");
        o1.setTable_number("T01");
        o1.setSett_amount(158.0);
        o1.setHang_status(1);
        o1.setHang_time(new Date(System.currentTimeMillis() - 120000)); // 2 分钟前
        o1.setHang_reason("等同伴");

        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(Collections.singletonList(o1));

        R r = controller.hangList();
        assertEquals(0, r.get("code"));
        List<?> list = (List<?>) r.get("list");
        assertNotNull(list);
        assertEquals(1, list.size());
        assertEquals(1, r.get("total"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<QueryWrapper<Order>> captor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(orderService).list(captor.capture());
        String sql = captor.getValue().getCustomSqlSegment();
        assertNotNull(sql);
        assertTrue(sql.contains("transac_status"));
        assertTrue(sql.contains("hang_status"));
        assertTrue(sql.contains("shop_id"));
        assertTrue(captor.getValue().getParamNameValuePairs().values().contains(2));
    }
}
