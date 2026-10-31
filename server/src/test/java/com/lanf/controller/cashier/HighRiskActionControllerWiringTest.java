package com.lanf.controller.cashier;

import com.lanf.access.model.AccessDecision;
import com.lanf.access.model.ApprovalRequirement;
import com.lanf.access.service.HighRiskActionAuthorizationService;
import com.lanf.controller.OrderController;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.order.OrderRevisionService;
import com.lanf.service.CashierCheckoutService;
import com.lanf.service.CashierClientRequestService;
import com.lanf.service.IOrderService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class HighRiskActionControllerWiringTest {

    @Test
    void cashierRefundReturnsThreeStateApprovalAndDoesNotReachBusinessMutation() {
        CashierOrderController controller = new CashierOrderController();
        HighRiskActionAuthorizationService authorization = mock(HighRiskActionAuthorizationService.class);
        CashierClientRequestService clientRequests = mock(CashierClientRequestService.class);
        IOrderService orders = mock(IOrderService.class);
        ITakeoutDeliveryService delivery = mock(ITakeoutDeliveryService.class);
        CashierCheckoutService checkout = mock(CashierCheckoutService.class);
        HighRiskActionAuthorizationService.Result result = mock(HighRiskActionAuthorizationService.Result.class);
        AccessDecision decision = AccessDecision.approvalRequired(
                ApprovalRequirement.builder().required(true)
                        .permission("order:operate:refund:approve").build(),
                "需要退款审批");
        when(result.isAllowed()).thenReturn(false);
        when(result.getCode()).thenReturn(40322);
        when(result.getDecision()).thenReturn(decision);
        when(authorization.authorize(any())).thenReturn(result);
        when(clientRequests.execute(anyInt(), anyInt(), anyString(), anyString(), any(), any()))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());
        Order order = paidOrder("ORD-R-1");
        when(orders.getOne(any())).thenReturn(order);
        when(delivery.getRefundBlockReason(order)).thenReturn(null);
        MockHttpServletRequest request = request();
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorization);
        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequests);
        ReflectionTestUtils.setField(controller, "orderService", orders);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", delivery);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkout);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-R-1");
        body.put("refundAmount", 12.30d);
        R response = controller.refund(body);

        assertEquals(40322, response.get("code"));
        assertEquals("REQUIRE_APPROVAL", response.get("outcome"));
        assertEquals("APPROVAL_REQUIRED", response.get("reasonCode"));
        verifyNoInteractions(checkout);
        ArgumentCaptor<HighRiskActionAuthorizationService.Request> captured =
                ArgumentCaptor.forClass(HighRiskActionAuthorizationService.Request.class);
        verify(authorization).authorize(captured.capture());
        assertEquals("order:operate:refund", captured.getValue().getPermissionCode());
        assertEquals("ORD-R-1", captured.getValue().getResourceId());
        assertEquals("12.3", captured.getValue().getAmount().stripTrailingZeros().toPlainString());
    }

    @Test
    void cashierUnCheckoutUsesExactReopenPermission() {
        CashierOrderController controller = new CashierOrderController();
        HighRiskActionAuthorizationService authorization = allowingAuthorization(9);
        CashierCheckoutService checkout = mock(CashierCheckoutService.class);
        when(checkout.unCheckout(7, "ORD-U-1")).thenReturn(R.ok().put("alreadyUnChecked", true));
        MockHttpServletRequest request = request();
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorization);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkout);
        ReflectionTestUtils.setField(controller, "request", request);
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-U-1");

        R response = controller.unCheckout(body);

        assertEquals(0, response.get("code"));
        ArgumentCaptor<HighRiskActionAuthorizationService.Request> captured =
                ArgumentCaptor.forClass(HighRiskActionAuthorizationService.Request.class);
        verify(authorization).authorize(captured.capture());
        assertEquals("order:operate:reopen", captured.getValue().getPermissionCode());
        assertEquals("ORD-U-1", captured.getValue().getResourceId());
        verify(checkout).unCheckout(7, "ORD-U-1");
    }

    @Test
    void refundDishAndUpdatePriceUseTheirExactActionPermissions() {
        CashierOrderController controller = new CashierOrderController();
        ReflectionTestUtils.setField(controller, "orderRevisionService", mock(OrderRevisionService.class));
        HighRiskActionAuthorizationService authorization = denyingAuthorization("blocked");
        CashierClientRequestService clientRequests = mock(CashierClientRequestService.class);
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);
        when(clientRequests.execute(anyInt(), anyInt(), anyString(), anyString(), any(), any()))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());
        Order dishOrder = new Order();
        dishOrder.setId(1);
        dishOrder.setOrder_no("ORD-D-1");
        dishOrder.setShop_id(7);
        dishOrder.setTransac_status("unsettled");
        OrderDetail detail = new OrderDetail();
        detail.setId(1);
        detail.setMId(1);
        detail.setMorder_no("ORD-D-1");
        detail.setQuantity("1");
        Order priceOrder = new Order();
        priceOrder.setId(2);
        priceOrder.setOrder_no("ORD-P-1");
        priceOrder.setShop_id(7);
        priceOrder.setTransac_status("unsettled");
        OrderDetail priceDetail = new OrderDetail();
        priceDetail.setId(2);
        priceDetail.setMId(2);
        priceDetail.setMorder_no("ORD-P-1");
        when(orders.getOne(any())).thenReturn(dishOrder, priceOrder);
        when(details.getOne(any())).thenReturn(detail);
        when(details.getById(2)).thenReturn(priceDetail);
        MockHttpServletRequest request = request();
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorization);
        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequests);
        ReflectionTestUtils.setField(controller, "orderService", orders);
        ReflectionTestUtils.setField(controller, "orderDetailService", details);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> refundDish = new HashMap<>();
        refundDish.put("order_no", "ORD-D-1");
        refundDish.put("detail_id", 1);
        refundDish.put("quantity", 1);
        controller.refundDish(refundDish);

        Map<String, Object> updatePrice = new HashMap<>();
        updatePrice.put("order_no", "ORD-P-1");
        updatePrice.put("detail_id", 2);
        updatePrice.put("total_price", 8.50d);
        controller.updatePrice(updatePrice);

        ArgumentCaptor<HighRiskActionAuthorizationService.Request> captured =
                ArgumentCaptor.forClass(HighRiskActionAuthorizationService.Request.class);
        verify(authorization, times(2)).authorize(captured.capture());
        assertEquals("order:operate:refund", captured.getAllValues().get(0).getPermissionCode());
        assertEquals("order:operate:changePrice", captured.getAllValues().get(1).getPermissionCode());
        assertEquals("8.5", captured.getAllValues().get(1).getAmount().stripTrailingZeros().toPlainString());
    }

    @Test
    void discountBindsCalculatedDiscountToExactPermission() {
        CashierOrderController controller = new CashierOrderController();
        ReflectionTestUtils.setField(controller, "orderRevisionService", mock(OrderRevisionService.class));
        HighRiskActionAuthorizationService authorization = denyingAuthorization("blocked");
        IOrderService orders = mock(IOrderService.class);
        WechatJsapiPaymentService payments = mock(WechatJsapiPaymentService.class);
        Order order = new Order();
        order.setId(10);
        order.setOrder_no("ORD-X-1");
        order.setShop_id(7);
        order.setTransac_status("unsettled");
        order.setSett_amount(100d);
        order.setService_fee(0d);
        when(orders.getOne(any())).thenReturn(order);
        when(payments.prepareForAmountMutation(order)).thenReturn(order);
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorization);
        ReflectionTestUtils.setField(controller, "orderService", orders);
        ReflectionTestUtils.setField(controller, "wechatJsapiPaymentService", payments);
        ReflectionTestUtils.setField(controller, "request", request());
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-X-1");
        body.put("payRate", 0.9d);

        R response = controller.discount(body);

        assertEquals(403, response.get("code"));
        ArgumentCaptor<HighRiskActionAuthorizationService.Request> captured =
                ArgumentCaptor.forClass(HighRiskActionAuthorizationService.Request.class);
        verify(authorization).authorize(captured.capture());
        assertEquals("order:operate:discount", captured.getValue().getPermissionCode());
        assertEquals("10", captured.getValue().getAmount().stripTrailingZeros().toPlainString());
    }

    @Test
    void adminWechatRefundUsesSharedExactRefundDecision() {
        AdminOrderController controller = new AdminOrderController();
        HighRiskActionAuthorizationService authorization = allowingAuthorization(22);
        OrderController orderController = mock(OrderController.class);
        when(orderController.refund(any(), eq(7))).thenReturn(R.ok());
        MockHttpServletRequest request = request();
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorization);
        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-WX-1");
        body.put("refundAmount", "30.00");

        R response = controller.wechatRefund(body);

        assertEquals(0, response.get("code"));
        ArgumentCaptor<HighRiskActionAuthorizationService.Request> captured =
                ArgumentCaptor.forClass(HighRiskActionAuthorizationService.Request.class);
        verify(authorization).authorize(captured.capture());
        assertEquals("order:operate:refund", captured.getValue().getPermissionCode());
        assertEquals("ORD-WX-1", captured.getValue().getResourceId());
        assertEquals("30.00", captured.getValue().getAmount().toPlainString());
        verify(orderController).refund(body, 7);
    }

    private static MockHttpServletRequest request() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        request.addHeader("X-Terminal-Id", "TERM-1");
        request.addHeader("X-Client-Request-Id", "REQ-1");
        return request;
    }

    private static HighRiskActionAuthorizationService allowingAuthorization(int authorizedAdminId) {
        HighRiskActionAuthorizationService service = mock(HighRiskActionAuthorizationService.class);
        HighRiskActionAuthorizationService.Result result = mock(HighRiskActionAuthorizationService.Result.class);
        when(result.isAllowed()).thenReturn(true);
        when(result.getAuthorizedAdminId()).thenReturn(authorizedAdminId);
        when(service.authorize(any())).thenReturn(result);
        return service;
    }

    private static HighRiskActionAuthorizationService denyingAuthorization(String explanation) {
        HighRiskActionAuthorizationService service = mock(HighRiskActionAuthorizationService.class);
        HighRiskActionAuthorizationService.Result result = mock(HighRiskActionAuthorizationService.Result.class);
        when(result.isAllowed()).thenReturn(false);
        when(result.getCode()).thenReturn(403);
        when(result.getDecision()).thenReturn(AccessDecision.deny("ACCESS_PERMISSION_DENIED", explanation));
        when(service.authorize(any())).thenReturn(result);
        return service;
    }

    private static Order paidOrder(String orderNo) {
        Order order = new Order();
        order.setId(1);
        order.setOrder_no(orderNo);
        order.setShop_id(7);
        order.setTransac_status("success");
        order.setSett_amount(100d);
        order.setService_fee(0d);
        order.setDiscount_amount(0d);
        order.setRefund_amount(0d);
        order.setPay_amount_cash(50d);
        return order;
    }
}
