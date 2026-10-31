package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatJsapiChannel;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.service.CashierCheckoutService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderControllerCashierContextTest {

    @Test
    void regularDineInOrder_shouldStillBlockPreopenedTable() {
        assertTrue(OrderController.shouldBlockPreopenedTable(true, null));
        assertTrue(OrderController.shouldBlockPreopenedTable(
                true, new MockHttpServletRequest()));
    }

    @Test
    void trustedCashierOrder_shouldClaimPreopenedTable() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(OrderController.CASHIER_QUICK_ORDER_ATTRIBUTE, Boolean.TRUE);

        assertFalse(OrderController.shouldBlockPreopenedTable(true, request));
        assertFalse(OrderController.shouldBlockPreopenedTable(false, request));
    }

    @Test
    void refund_shouldNeverSendExhaustedSyntheticCashierCombinedPaymentToWechat() {
        OrderController controller = new OrderController();
        IOrderService orderService = mock(IOrderService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        CashierCheckoutService cashierCheckoutService = mock(CashierCheckoutService.class);
        WechatJsapiChannel wechat = mock(WechatJsapiChannel.class);
        Order order = new Order();
        order.setOrder_no("ORD-COMBINED-REFUND");
        order.setTransac_status("success");
        order.setPayment_method(PaymentChannelCatalog.NAME_COMBINED_PAY);
        order.setTransaction_id("CASHIER_COMBINED_ORD-COMBINED-REFUND");
        order.setBalance_pay_principal(0d);
        order.setBalance_pay_gift_wallet(0d);
        order.setPay_amount_cash(100d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", cashierCheckoutService);
        ReflectionTestUtils.setField(controller, "wechatJsapiChannel", wechat);
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-COMBINED-REFUND");

        R result = controller.refund(body);

        assertEquals(500, result.get("code"));
        assertEquals("组合支付剩余现金或线下扫码部分需人工退款并完成账务核对，禁止发起自动微信退款",
                result.get("msg"));
        verify(cashierCheckoutService, never()).refundWalletComponent(
                anyString(), any(Map.class));
        verify(wechat, never()).domesticRefund(
                any(Order.class), anyInt(), anyInt(), anyString(), anyString());
    }

    @Test
    void refund_receivableOrderMustUseReceivableWorkflowInsteadOfPaymentRefund() {
        OrderController controller = new OrderController();
        IOrderService orderService = mock(IOrderService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        WechatJsapiChannel wechat = mock(WechatJsapiChannel.class);
        Order order = new Order();
        order.setOrder_no("ORD-AR-REFUND");
        order.setTransac_status("success");
        order.setPayment_method("挂账");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "wechatJsapiChannel", wechat);
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-AR-REFUND");

        R result = controller.refund(body);

        assertEquals(409, result.get("code"));
        verify(deliveryService, never()).getRefundBlockReason(any(Order.class));
        verify(wechat, never()).domesticRefund(
                any(Order.class), anyInt(), anyInt(), anyString(), anyString());
    }

    @Test
    void refund_scopesOrderLookupToRequiredShop() {
        OrderController controller = new OrderController();
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORDER-FROM-ANOTHER-SHOP");

        R result = controller.refund(body, 7);

        assertEquals(500, result.get("code"));
        verify(orderService).getOne(argThat(wrapper ->
                wrapper.getSqlSegment().contains("shop_id")));
    }
}
