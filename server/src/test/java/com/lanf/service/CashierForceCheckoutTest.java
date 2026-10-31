package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.access.service.ApprovalService;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.security.SecurityAuditService;
import com.lanf.security.SensitiveOperationAuthorizationService;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.controller.cashier.CashierTableController;
import com.lanf.entity.Table;
import com.lanf.interceptor.SysInterceptor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class CashierForceCheckoutTest {

    private CashierCheckoutService service;
    private IOrderService orderService;
    private ITableService tableService;
    private IUserService userService;
    private PaymentCapabilityService capabilities;
    private UserCouponMapper userCouponMapper;
    private CashierCollectionIntentService collectionIntentService;
    private IAdminPermissionService adminPermissionService;
    private IAdminShopAccessService adminShopAccessService;
    private SecurityAuditService securityAuditService;
    private Order order;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        service = new CashierCheckoutService();
        orderService = mock(IOrderService.class);
        tableService = mock(ITableService.class);
        userService = mock(IUserService.class);
        capabilities = mock(PaymentCapabilityService.class);
        userCouponMapper = mock(UserCouponMapper.class);
        collectionIntentService = mock(CashierCollectionIntentService.class);
        adminPermissionService = mock(IAdminPermissionService.class);
        adminShopAccessService = mock(IAdminShopAccessService.class);
        securityAuditService = mock(SecurityAuditService.class);

        request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "tableService", tableService);
        ReflectionTestUtils.setField(service, "userService", userService);
        ReflectionTestUtils.setField(service, "paymentCapabilityService", capabilities);
        ReflectionTestUtils.setField(service, "userCouponMapper", userCouponMapper);
        ReflectionTestUtils.setField(service, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(service, "adminPermissionService", adminPermissionService);
        ReflectionTestUtils.setField(service, "adminShopAccessService", adminShopAccessService);
        ReflectionTestUtils.setField(service, "securityAuditService", securityAuditService);
        ReflectionTestUtils.setField(service, "httpServletRequest", request);
        ReflectionTestUtils.setField(service, "paymentSuccessHandler", mock(com.lanf.payment.success.PaymentSuccessHandler.class));
        ReflectionTestUtils.setField(service, "paymentLedgerService", mock(PaymentLedgerService.class));
        WechatJsapiPaymentService jsapiPaymentService = mock(WechatJsapiPaymentService.class);
        when(jsapiPaymentService.prepareForAmountMutation(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        ReflectionTestUtils.setField(service, "wechatJsapiPaymentService", jsapiPaymentService);

        order = new Order();
        order.setId(100);
        order.setOrder_no("ORD-FORCE-1");
        order.setShop_id(1);
        order.setTransac_status("unsettled");
        order.setSett_amount(88.0);
        order.setDiscount_amount(0.0);
        order.setService_fee(0.0);
        order.setDineInOrTakeOut("打包");

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(1), anyString())).thenReturn(true);
        when(orderService.updateById(any(Order.class))).thenReturn(true);
    }

    @Test
    void forceCheckout_withoutAdminManagePermission_shouldRejectWith403() {
        request.setAttribute("adminId", 99);
        when(adminShopAccessService.isSuperAdmin(99)).thenReturn(false);
        when(adminPermissionService.getPermissionCodesByAdminId(99)).thenReturn(Collections.singleton("order:view"));

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-FORCE-1");
        body.put("payment_method", PaymentChannelCatalog.CASH);
        body.put("force", true);

        R res = service.checkout(1, body);

        assertEquals(403, res.get("code"));
        assertTrue(res.get("msg").toString().contains("admin:manage"));
        verify(orderService, never()).updateById(any());
        verify(collectionIntentService, never()).completeAllForOrder(anyInt(), anyString());
    }

    @Test
    void forceCheckout_withAdminManagePermission_shouldSucceedAndCompleteAllIntents() {
        request.setAttribute("adminId", 2);
        when(adminShopAccessService.isSuperAdmin(2)).thenReturn(false);
        when(adminPermissionService.getPermissionCodesByAdminId(2)).thenReturn(
                new java.util.HashSet<>(java.util.Arrays.asList("admin:manage", "cashier:operate")));

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-FORCE-1");
        body.put("payment_method", PaymentChannelCatalog.CASH);
        body.put("force", true);

        R res = service.checkout(1, body);

        assertEquals(0, res.get("code"));
        assertEquals(Boolean.TRUE, res.get("forced"));
        verify(collectionIntentService).completeAllForOrder(1, "ORD-FORCE-1");
        verify(securityAuditService).recordPrivilegedAction(
                eq(request), eq(1), eq("cashier"), eq("FORCE_CHECKOUT"), eq("ORD-FORCE-1"), eq(2), anyMap(), anyString());
    }

    @Test
    void forceCheckout_withSuperAdmin_shouldSucceedEvenWithoutExplicitCode() {
        request.setAttribute("adminId", 1);
        when(adminShopAccessService.isSuperAdmin(1)).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-FORCE-1");
        body.put("payment_method", PaymentChannelCatalog.CASH);
        body.put("force", true);

        R res = service.checkout(1, body);

        assertEquals(0, res.get("code"));
        assertEquals(Boolean.TRUE, res.get("forced"));
        verify(collectionIntentService).completeAllForOrder(1, "ORD-FORCE-1");
        verify(securityAuditService).recordPrivilegedAction(
                eq(request), eq(1), eq("cashier"), eq("FORCE_CHECKOUT"), eq("ORD-FORCE-1"), eq(1), anyMap(), anyString());
    }

    @Test
    void checkForceCheckoutPermission_withPreAuthorizationFlag_shouldBypass() {
        Map<String, Object> body = new HashMap<>();
        body.put("_forcePreAuthorized", true);
        body.put("_authorizedAdminId", 88);

        Integer[] authorizedAdminIdOut = new Integer[1];
        R res = service.checkForceCheckoutPermission(1, body, authorizedAdminIdOut);

        assertNull(res);
        assertEquals(88, authorizedAdminIdOut[0]);
    }

    @Test
    void tableCheckout_forceWithoutPermission_shouldRejectWith403() {
        CashierTableController tableController = new CashierTableController();
        ReflectionTestUtils.setField(tableController, "orderService", orderService);
        ReflectionTestUtils.setField(tableController, "tableService", tableService);
        ReflectionTestUtils.setField(tableController, "cashierCheckoutService", service);
        ReflectionTestUtils.setField(tableController, "request", request);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 99);
        when(adminShopAccessService.isSuperAdmin(99)).thenReturn(false);
        when(adminPermissionService.getPermissionCodesByAdminId(99)).thenReturn(Collections.singleton("order:view"));

        Table table = new Table();
        table.setNumber("A01");
        table.setShop_id(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));

        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "A01");
        body.put("paymentMethod", "cash");
        body.put("force", true);

        R res = tableController.checkout(body);

        assertEquals(403, res.get("code"));
        assertTrue(res.get("msg").toString().contains("admin:manage"));
    }

    @Test
    void tableCheckout_forceWithPermission_shouldSucceedAndEchoForced() {
        CashierTableController tableController = new CashierTableController();
        ReflectionTestUtils.setField(tableController, "orderService", orderService);
        ReflectionTestUtils.setField(tableController, "tableService", tableService);
        ReflectionTestUtils.setField(tableController, "cashierCheckoutService", service);
        ReflectionTestUtils.setField(tableController, "request", request);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 2);
        when(adminShopAccessService.isSuperAdmin(2)).thenReturn(false);
        when(adminPermissionService.getPermissionCodesByAdminId(2)).thenReturn(
                new java.util.HashSet<>(java.util.Arrays.asList("admin:manage", "cashier:operate")));

        Table table = new Table();
        table.setNumber("A01");
        table.setShop_id(1);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);
        when(tableService.updateById(any())).thenReturn(true);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));

        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "A01");
        body.put("paymentMethod", "cash");
        body.put("force", true);

        R res = tableController.checkout(body);

        assertEquals(0, res.get("code"));
        assertEquals(Boolean.TRUE, res.get("forced"));
        verify(collectionIntentService).completeAllForOrder(1, "ORD-FORCE-1");
    }

    @Test
    void adminCheckout_forceWithoutPermission_shouldRejectWith403() {
        AdminOrderController adminController = new AdminOrderController();
        ReflectionTestUtils.setField(adminController, "orderService", orderService);
        ReflectionTestUtils.setField(adminController, "tableService", tableService);
        ReflectionTestUtils.setField(adminController, "paymentCapabilityService", capabilities);
        ReflectionTestUtils.setField(adminController, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(adminController, "cashierCheckoutService", service);
        ReflectionTestUtils.setField(adminController, "securityAuditService", securityAuditService);
        ReflectionTestUtils.setField(adminController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminController, "userCouponMapper", userCouponMapper);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 99);
        when(adminShopAccessService.isSuperAdmin(99)).thenReturn(false);
        when(adminPermissionService.getPermissionCodesByAdminId(99)).thenReturn(Collections.singleton("order:view"));

        Order param = new Order();
        param.setId(100);
        param.setOrder_no("ORD-FORCE-1");
        param.setTransac_status("success");
        param.setPayment_method("cash");
        param.setForce(true);

        when(orderService.getById(100)).thenReturn(order);

        R res = adminController.checkout(param);

        assertEquals(403, res.get("code"));
        assertTrue(res.get("msg").toString().contains("admin:manage"));
    }

    @Test
    void adminCheckout_forceWithPermission_shouldSucceedAndEchoForced() {
        AdminOrderController adminController = new AdminOrderController();
        ReflectionTestUtils.setField(adminController, "orderService", orderService);
        ReflectionTestUtils.setField(adminController, "tableService", tableService);
        ReflectionTestUtils.setField(adminController, "paymentCapabilityService", capabilities);
        ReflectionTestUtils.setField(adminController, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(adminController, "cashierCheckoutService", service);
        ReflectionTestUtils.setField(adminController, "securityAuditService", securityAuditService);
        ReflectionTestUtils.setField(adminController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminController, "userCouponMapper", userCouponMapper);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 2);
        when(adminShopAccessService.isSuperAdmin(2)).thenReturn(false);
        when(adminPermissionService.getPermissionCodesByAdminId(2)).thenReturn(
                new java.util.HashSet<>(java.util.Arrays.asList("admin:manage", "order:operate")));

        Order param = new Order();
        param.setId(100);
        param.setOrder_no("ORD-FORCE-1");
        param.setTransac_status("success");
        param.setPayment_method("cash");
        param.setForce(true);

        when(orderService.getById(100)).thenReturn(order);

        R res = adminController.checkout(param);

        assertEquals(0, res.get("code"));
        assertEquals(Boolean.TRUE, res.get("forced"));
        verify(collectionIntentService).completeAllForOrder(1, "ORD-FORCE-1");
        verify(securityAuditService).recordPrivilegedAction(
                eq(request), eq(1), eq("cashier"), eq("FORCE_CHECKOUT"), eq("ORD-FORCE-1"), eq(2), anyMap(), anyString());
    }

    @Test
    void adminCheckout_normalWithConflictingIntent_shouldFailIntentValidation() {
        AdminOrderController adminController = new AdminOrderController();
        ReflectionTestUtils.setField(adminController, "orderService", orderService);
        ReflectionTestUtils.setField(adminController, "tableService", tableService);
        ReflectionTestUtils.setField(adminController, "paymentCapabilityService", capabilities);
        ReflectionTestUtils.setField(adminController, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(adminController, "cashierCheckoutService", service);
        ReflectionTestUtils.setField(adminController, "securityAuditService", securityAuditService);
        ReflectionTestUtils.setField(adminController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminController, "userCouponMapper", userCouponMapper);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 2);

        doThrow(new IllegalStateException("该订单已有扫码款确认到账，不能更换为其他支付方式"))
                .when(collectionIntentService)
                .validateCheckout(eq(1), eq("ORD-FORCE-1"), isNull(), anyInt(), anyInt(), eq(false));

        Order param = new Order();
        param.setId(100);
        param.setOrder_no("ORD-FORCE-1");
        param.setTransac_status("success");
        param.setPayment_method("cash");
        param.setForce(false);

        when(orderService.getById(100)).thenReturn(order);

        R res = adminController.checkout(param);

        assertEquals(500, res.get("code"));
        assertTrue(res.get("msg").toString().contains("已有扫码款确认到账"));
        verify(orderService, never()).updateById(any());
        verify(collectionIntentService, never()).completeAllForOrder(anyInt(), anyString());
    }

    @Test
    void adminCheckout_normalClean_shouldNotCallCompleteAllForOrder() {
        AdminOrderController adminController = new AdminOrderController();
        ReflectionTestUtils.setField(adminController, "orderService", orderService);
        ReflectionTestUtils.setField(adminController, "tableService", tableService);
        ReflectionTestUtils.setField(adminController, "paymentCapabilityService", capabilities);
        ReflectionTestUtils.setField(adminController, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(adminController, "cashierCheckoutService", service);
        ReflectionTestUtils.setField(adminController, "securityAuditService", securityAuditService);
        ReflectionTestUtils.setField(adminController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminController, "userCouponMapper", userCouponMapper);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 2);

        Order param = new Order();
        param.setId(100);
        param.setOrder_no("ORD-FORCE-1");
        param.setTransac_status("success");
        param.setPayment_method("cash");
        param.setForce(false);

        when(orderService.getById(100)).thenReturn(order);

        R res = adminController.checkout(param);

        assertEquals(0, res.get("code"));
        assertNull(res.get("forced"));
        verify(collectionIntentService).validateCheckout(eq(1), eq("ORD-FORCE-1"), isNull(), anyInt(), anyInt(), eq(false));
        verify(collectionIntentService, never()).completeAllForOrder(anyInt(), anyString());
    }
}
