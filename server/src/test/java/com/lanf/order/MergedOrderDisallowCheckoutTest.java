package com.lanf.order;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.payment.facade.PaymentFacadeService;
import com.lanf.payment.service.PaymentOnlineGuardService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class MergedOrderDisallowCheckoutTest {

    private AdminOrderController adminOrderController;
    private PaymentFacadeService paymentFacadeService;
    private IOrderService orderService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        orderService = mock(IOrderService.class);
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        adminOrderController = new AdminOrderController();
        ReflectionTestUtils.setField(adminOrderController, "orderService", orderService);
        ReflectionTestUtils.setField(adminOrderController, "httpServletRequest", request);

        paymentFacadeService = new PaymentFacadeService();
        PaymentOnlineGuardService guardService = mock(PaymentOnlineGuardService.class);
        ReflectionTestUtils.setField(paymentFacadeService, "orderService", orderService);
        ReflectionTestUtils.setField(paymentFacadeService, "paymentOnlineGuardService", guardService);
        ReflectionTestUtils.setField(paymentFacadeService, "paymentNotifyState", new com.lanf.payment.support.PaymentNotifyState());
    }

    @Test
    void adminCheckout_whenOrderIsMergedSlaveOrder_shouldReject() {
        Order dbOrder = new Order();
        dbOrder.setId(101);
        dbOrder.setOrder_no("SLAVE-01");
        dbOrder.setShop_id(1);
        dbOrder.setTransac_status("unsettled");
        dbOrder.setMaster_order_no("MASTER-01");

        when(orderService.getById(101)).thenReturn(dbOrder);

        Order param = new Order();
        param.setId(101);
        param.setTransac_status("success");

        R r = adminOrderController.checkout(param);

        assertEquals(500, r.get("code"));
        assertEquals("该订单为并台从单，不支持单独结账，请通过主桌统一结账", r.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void adminCheckout_whenMasterOrderHasUnsettledSlaveOrders_shouldReject() {
        Order dbOrder = new Order();
        dbOrder.setId(100);
        dbOrder.setOrder_no("MASTER-01");
        dbOrder.setShop_id(1);
        dbOrder.setTransac_status("unsettled");

        when(orderService.getById(100)).thenReturn(dbOrder);
        when(orderService.count(any(Wrapper.class))).thenReturn(1);

        Order param = new Order();
        param.setId(100);
        param.setTransac_status("success");

        R r = adminOrderController.checkout(param);

        assertEquals(500, r.get("code"));
        assertEquals("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账", r.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void paymentFacade_getPrepayId_whenOrderIsMergedSlaveOrder_shouldReject() {
        Order dbOrder = new Order();
        dbOrder.setId(201);
        dbOrder.setOrder_no("SLAVE-02");
        dbOrder.setShop_id(1);
        dbOrder.setTransac_status("unsettled");
        dbOrder.setMaster_order_no("MASTER-02");
        dbOrder.setOpenid("user-openid");

        when(orderService.getOne(any(Wrapper.class))).thenReturn(dbOrder);

        Map<String, String> params = new HashMap<>();
        params.put("orderNo", "SLAVE-02");
        params.put("openid", "user-openid");

        R r = paymentFacadeService.getPrepayId(params);

        assertEquals(500, r.get("code"));
        assertEquals("该订单为并台从单，不支持单独结账，请通过主桌统一结账", r.get("msg"));
    }

    @Test
    void paymentFacade_payByBalance_whenOrderIsMergedSlaveOrder_shouldReject() {
        Order dbOrder = new Order();
        dbOrder.setId(201);
        dbOrder.setOrder_no("SLAVE-02");
        dbOrder.setShop_id(1);
        dbOrder.setTransac_status("unsettled");
        dbOrder.setMaster_order_no("MASTER-02");
        dbOrder.setOpenid("user-openid");

        when(orderService.getOne(any(Wrapper.class))).thenReturn(dbOrder);

        Map<String, String> params = new HashMap<>();
        params.put("orderNo", "SLAVE-02");
        params.put("openid", "user-openid");

        R r = paymentFacadeService.payByBalance(params);

        assertEquals(500, r.get("code"));
        assertEquals("该订单为并台从单，不支持单独结账，请通过主桌统一结账", r.get("msg"));
    }
}
