package com.lanf.controller;

import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.security.SecurityAuditService;
import com.lanf.security.SensitiveOperationAuthorizationService;
import com.lanf.entity.Admin;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.math.BigDecimal;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderControllerDeleteSecurityTest {

    @Test
    void nonSuperAdminCannotDeleteOrder() {
        Fixture fixture = fixture(false);

        R result = fixture.controller.deleteOrder(13573, java.util.Collections.emptyMap(), fixture.request);

        assertEquals(403, result.get("code"));
        assertEquals("仅超级管理员可删除订单", result.get("msg"));
        verify(fixture.orderService, never()).getById(any());
        verify(fixture.auditService).recordAccessDenied(
                eq(fixture.request), eq(9), eq(null), eq(403),
                eq("super_admin_required_for_order_delete"), eq("super_admin"));
    }

    @Test
    void superAdminCanDeleteCompletedTakeoutWithoutDeliveryStateRestriction() {
        Fixture fixture = fixture(true);
        Order order = new Order();
        order.setId(13573);
        order.setOrder_no("ORDER-13573");
        order.setShop_id(2);
        order.setDineInOrTakeOut("外卖");
        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(13573);
        delivery.setDispatch_status("completed");
        when(fixture.orderService.getById(13573)).thenReturn(order);
        when(fixture.deliveryService.getByOrderId(13573)).thenReturn(delivery);

        Admin authorizer = new Admin();
        authorizer.setId(22);
        when(fixture.authorizationService.authorize(any(), eq("order:delete"), eq(2), eq(true)))
                .thenReturn(SensitiveOperationAuthorizationService.Decision.allowed(authorizer));

        R result = fixture.controller.deleteOrder(13573, java.util.Collections.emptyMap(), fixture.request);

        assertEquals(0, result.get("code"));
        assertEquals("订单删除成功", result.get("msg"));
        verify(fixture.deliveryService, never()).getOrderDeleteBlockReason(any());
        verify(fixture.deliveryService).deleteByOrderId(13573);
        verify(fixture.orderDetailService).remove(any());
        verify(fixture.orderService).removeById(13573);
        verify(fixture.auditService).recordPrivilegedAction(
                eq(fixture.request), eq(2), eq("order"), eq("force_delete"),
                eq("13573"), eq(9), any(), eq("order_force_deleted_by_super_admin"));
    }

    @Test
    void validApprovalTokenAllowsSuperAdminDelete() {
        Fixture fixture = fixture(true);
        Order order = new Order();
        order.setId(13573);
        order.setOrder_no("ORDER-13573");
        order.setShop_id(2);
        when(fixture.orderService.getById(13573)).thenReturn(order);

        com.lanf.access.service.ApprovalService approvalService =
                mock(com.lanf.access.service.ApprovalService.class);
        ReflectionTestUtils.setField(fixture.controller, "approvalService", approvalService);
        when(approvalService.validateAndConsume(eq("tok-valid"), any(com.lanf.access.model.AccessContext.class)))
                .thenReturn(true);

        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("approvalToken", "tok-valid");
        R result = fixture.controller.deleteOrder(13573, body, fixture.request);

        assertEquals(0, result.get("code"));
        assertEquals("订单删除成功", result.get("msg"));
        verify(fixture.orderService).removeById(13573);
        verify(fixture.auditService).recordPrivilegedAction(
                eq(fixture.request), eq(2), eq("order"), eq("force_delete"),
                eq("13573"), eq(9), any(), eq("order_force_deleted_by_super_admin"));
        verify(fixture.authorizationService, never()).authorize(any(), any(), any(), anyBoolean());
    }

    @Test
    void deleteOrderPassesHeaderTerminalAndFallbackOrderAmountToContext() {
        Fixture fixture = fixture(true);
        fixture.request.addHeader("X-Terminal-Id", "cashier-pos-001");
        Order order = new Order();
        order.setId(13573);
        order.setOrder_no("ORDER-13573");
        order.setShop_id(2);
        order.setSett_amount(58.00);
        when(fixture.orderService.getById(13573)).thenReturn(order);

        com.lanf.access.service.ApprovalService approvalService =
                mock(com.lanf.access.service.ApprovalService.class);
        ReflectionTestUtils.setField(fixture.controller, "approvalService", approvalService);
        ArgumentCaptor<com.lanf.access.model.AccessContext> captor =
                ArgumentCaptor.forClass(com.lanf.access.model.AccessContext.class);
        when(approvalService.validateAndConsume(eq("tok-test"), captor.capture())).thenReturn(true);

        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("approvalToken", "tok-test");
        R result = fixture.controller.deleteOrder(13573, body, fixture.request);

        assertEquals(0, result.get("code"));
        com.lanf.access.model.AccessContext ctx = captor.getValue();
        assertEquals("cashier-pos-001", ctx.getTerminalId());
        assertEquals(new BigDecimal("58.00"), ctx.getAmount());
        assertEquals("order:delete", ctx.getPermissionCode());
        assertEquals("ORDER", ctx.getResourceType());
        assertEquals("ORDER-13573", ctx.getResourceId());
    }

    @Test
    void deleteOrderPassesBodyTerminalAndExplicitAmountToContext() {
        Fixture fixture = fixture(true);
        // Header 无 terminalId，由 body 传递
        Order order = new Order();
        order.setId(13573);
        order.setOrder_no("ORDER-13573");
        order.setShop_id(2);
        order.setSett_amount(100.00);
        when(fixture.orderService.getById(13573)).thenReturn(order);

        com.lanf.access.service.ApprovalService approvalService =
                mock(com.lanf.access.service.ApprovalService.class);
        ReflectionTestUtils.setField(fixture.controller, "approvalService", approvalService);
        ArgumentCaptor<com.lanf.access.model.AccessContext> captor =
                ArgumentCaptor.forClass(com.lanf.access.model.AccessContext.class);
        when(approvalService.validateAndConsume(eq("tok-test-2"), captor.capture())).thenReturn(true);

        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("approvalToken", "tok-test-2");
        body.put("terminalId", "cashier-pos-002");
        body.put("amount", "88.50");
        R result = fixture.controller.deleteOrder(13573, body, fixture.request);

        assertEquals(0, result.get("code"));
        com.lanf.access.model.AccessContext ctx = captor.getValue();
        assertEquals("cashier-pos-002", ctx.getTerminalId());
        assertEquals(new BigDecimal("88.50"), ctx.getAmount());
    }

    @Test
    void invalidApprovalTokenRejectsDeleteWithoutFallingBack() {
        Fixture fixture = fixture(true);
        Order order = new Order();
        order.setId(13573);
        order.setOrder_no("ORDER-13573");
        order.setShop_id(2);
        when(fixture.orderService.getById(13573)).thenReturn(order);

        com.lanf.access.service.ApprovalService approvalService =
                mock(com.lanf.access.service.ApprovalService.class);
        ReflectionTestUtils.setField(fixture.controller, "approvalService", approvalService);
        when(approvalService.validateAndConsume(any(), any())).thenReturn(false);

        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("approvalToken", "tok-invalid");
        R result = fixture.controller.deleteOrder(13573, body, fixture.request);

        assertEquals(40321, result.get("code"));
        assertEquals("授权令牌无效、已过期或不匹配当前业务", result.get("msg"));
        verify(fixture.orderService, never()).removeById(any());
        verify(fixture.auditService).recordAccessDenied(
                eq(fixture.request), eq(9), eq(2), eq(40321),
                eq("order_delete_approval_token_invalid"), eq("order:delete"));
        verify(fixture.authorizationService, never()).authorize(any(), any(), any(), anyBoolean());
    }

    private static Fixture fixture(boolean superAdmin) {
        Fixture fixture = new Fixture();
        fixture.controller = new OrderController();
        fixture.orderService = mock(IOrderService.class);
        fixture.orderDetailService = mock(IOrderDetailService.class);
        fixture.deliveryService = mock(ITakeoutDeliveryService.class);
        fixture.adminShopAccessService = mock(IAdminShopAccessService.class);
        fixture.auditService = mock(SecurityAuditService.class);
        fixture.authorizationService = mock(SensitiveOperationAuthorizationService.class);
        fixture.request = new MockHttpServletRequest("DELETE", "/order/delete/13573");
        fixture.request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        when(fixture.adminShopAccessService.isSuperAdmin(9)).thenReturn(superAdmin);
        ReflectionTestUtils.setField(fixture.controller, "orderService", fixture.orderService);
        ReflectionTestUtils.setField(fixture.controller, "orderDetailService", fixture.orderDetailService);
        ReflectionTestUtils.setField(fixture.controller, "takeoutDeliveryService", fixture.deliveryService);
        ReflectionTestUtils.setField(fixture.controller, "adminShopAccessService", fixture.adminShopAccessService);
        ReflectionTestUtils.setField(fixture.controller, "securityAuditService", fixture.auditService);
        ReflectionTestUtils.setField(fixture.controller, "sensitiveOperationAuthorizationService", fixture.authorizationService);
        ReflectionTestUtils.setField(fixture.controller, "kdsOrderHook", mock(KdsOrderHook.class));
        return fixture;
    }

    private static final class Fixture {
        private OrderController controller;
        private IOrderService orderService;
        private IOrderDetailService orderDetailService;
        private ITakeoutDeliveryService deliveryService;
        private IAdminShopAccessService adminShopAccessService;
        private SecurityAuditService auditService;
        private SensitiveOperationAuthorizationService authorizationService;
        private MockHttpServletRequest request;
    }
}
