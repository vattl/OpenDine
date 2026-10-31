package com.lanf.isolation;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.constant.AdminDataScope;
import com.lanf.controller.OrderController;
import com.lanf.controller.admin.AdminMemberController;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.ShopMemberWallet;
import com.lanf.entity.User;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.MemberCrossShopClearingMapper;
import com.lanf.mapper.ShopMemberWalletMapper;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.*;
import com.lanf.service.impl.ShopMemberWalletServiceImpl;
import com.lanf.util.SystemConfigTableSupport;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class MultiStoreIsolationAndCrossShopWalletTest {

    private AdminMemberController adminMemberController;
    private AdminOrderController adminOrderController;
    private ShopMemberWalletServiceImpl shopMemberWalletService;

    private IUserService userService;
    private IMemberRechargeService memberRechargeService;
    private IOrderService orderService;
    private IAdminShopAccessService adminShopAccessService;
    private AdminShopScopeGuard adminShopScopeGuard;
    private ShopMemberWalletMapper shopMemberWalletMapper;
    private MemberCrossShopClearingMapper crossShopClearingMapper;
    private SystemConfigMapper systemConfigMapper;
    private SystemConfigTableSupport systemConfigTableSupport;

    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 100);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        userService = mock(IUserService.class);
        memberRechargeService = mock(IMemberRechargeService.class);
        orderService = mock(IOrderService.class);
        adminShopAccessService = mock(IAdminShopAccessService.class);
        shopMemberWalletMapper = mock(ShopMemberWalletMapper.class);
        crossShopClearingMapper = mock(MemberCrossShopClearingMapper.class);
        systemConfigMapper = mock(SystemConfigMapper.class);
        systemConfigTableSupport = mock(SystemConfigTableSupport.class);
        IShiftService shiftService = mock(IShiftService.class);

        adminShopScopeGuard = new AdminShopScopeGuard(request, adminShopAccessService);

        shopMemberWalletService = new ShopMemberWalletServiceImpl();
        ReflectionTestUtils.setField(shopMemberWalletService, "baseMapper", shopMemberWalletMapper);
        ReflectionTestUtils.setField(shopMemberWalletService, "systemConfigMapper", systemConfigMapper);
        ReflectionTestUtils.setField(shopMemberWalletService, "systemConfigTableSupport", systemConfigTableSupport);
        ReflectionTestUtils.setField(shopMemberWalletService, "crossShopClearingMapper", crossShopClearingMapper);
        ReflectionTestUtils.setField(shopMemberWalletService, "userService", userService);

        adminMemberController = new AdminMemberController();
        ReflectionTestUtils.setField(adminMemberController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminMemberController, "adminShopScopeGuard", adminShopScopeGuard);
        ReflectionTestUtils.setField(adminMemberController, "userService", userService);
        ReflectionTestUtils.setField(adminMemberController, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(adminMemberController, "orderService", orderService);
        ReflectionTestUtils.setField(adminMemberController, "adminShopAccessService", adminShopAccessService);
        ReflectionTestUtils.setField(adminMemberController, "shopMemberWalletService", shopMemberWalletService);
        ReflectionTestUtils.setField(adminMemberController, "shiftService", shiftService);

        adminOrderController = new AdminOrderController();
        ReflectionTestUtils.setField(adminOrderController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminOrderController, "adminShopScopeGuard", adminShopScopeGuard);
        ReflectionTestUtils.setField(adminOrderController, "adminShopAccessService", adminShopAccessService);
        ReflectionTestUtils.setField(adminOrderController, "UserService", userService);
    }

    // ==================== Stage 1: Isolation Tests ====================

    @Test
    void testRechargeDeniedWhenStoreAdminCrossesStore() {
        // Given store admin bound only to store 1
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.SHOP);
        when(adminShopAccessService.listAccessibleShopIds(100)).thenReturn(Collections.singleton(1));
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        User u = new User();
        u.setId(10);
        u.setOpenid("test_openid_10");
        when(userService.getUserByPhone("13800138000")).thenReturn(u);

        // Attempting to inject shop_id = 2 in body
        Map<String, Object> body = new HashMap<>();
        body.put("phone", "13800138000");
        body.put("amount", "100.00");
        body.put("shop_id", 2);

        R res = adminMemberController.recharge(body);
        assertEquals(4003, res.get("code"));
        assertTrue(res.get("msg").toString().contains("不一致") || res.get("msg").toString().contains("不可操作"));
    }

    @Test
    void testRechargeSucceedsWithAuthorizedShop() {
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.SHOP);
        when(adminShopAccessService.listAccessibleShopIds(100)).thenReturn(Collections.singleton(1));
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        User u = new User();
        u.setId(10);
        u.setOpenid("test_openid_10");
        when(userService.getUserByPhone("13800138000")).thenReturn(u);
        when(userService.addBalanceAndGift(eq(10), any(), any())).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("phone", "13800138000");
        body.put("amount", "100.00");
        body.put("shop_id", 1);

        R res = adminMemberController.recharge(body);
        assertEquals(0, res.get("code"));
        verify(memberRechargeService).recordAdminSuccess(eq(10), eq("test_openid_10"), eq(1), eq(100), any(), any(), any(), any());
    }

    @Test
    void testDeductBalanceRequiresReason() {
        request.addHeader("X-Shop-Id", "1");
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.HQ);

        Map<String, Object> body = new HashMap<>();
        body.put("phone", "13800138000");
        body.put("amount", "50.00");
        // No reason provided

        R res = adminMemberController.deductBalance(body);
        assertNotEquals(0, res.get("code"));
        assertTrue(res.get("msg").toString().contains("扣减原因不能为空"));
    }

    @Test
    void testDeductBalanceRequiresShopContext() {
        // No X-Shop-Id header, and store admin with no shop specified
        request.removeAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.SHOP);

        Map<String, Object> body = new HashMap<>();
        body.put("phone", "13800138000");
        body.put("amount", "50.00");
        body.put("reason", "客户要求线下退差价");

        R res = adminMemberController.deductBalance(body);
        assertEquals(4003, res.get("code"));
    }

    @Test
    void testDeductBalanceSucceedsAndAudits() {
        request.addHeader("X-Shop-Id", "1");
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.SHOP);
        when(adminShopAccessService.listAccessibleShopIds(100)).thenReturn(Collections.singleton(1));

        User u = new User();
        u.setId(10);
        u.setOpenid("test_openid_10");
        when(userService.getUserByPhone("13800138000")).thenReturn(u);
        when(userService.subtractWalletProportionalIfEnough(eq(10), any())).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("phone", "13800138000");
        body.put("amount", "50.00");
        body.put("reason", "线下现金退款");

        R res = adminMemberController.deductBalance(body);
        assertEquals(0, res.get("code"));
        verify(memberRechargeService).recordAdminSuccess(eq(10), eq("test_openid_10"), eq(1), eq(100), isNull(),
                eq(new BigDecimal("-50.00")), eq(BigDecimal.ZERO), contains("线下现金退款"));
    }

    @Test
    void testAddPointsRequiresShopContext() {
        // No shop context
        request.removeAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.HQ);
        Map<String, Object> body = new HashMap<>();
        body.put("openid", "test_openid_10");
        body.put("points", 100);

        R res = adminOrderController.addPoints(body);
        assertEquals(4001, res.get("code"));
    }

    @Test
    void testAddPointsWithShopContextSucceeds() {
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        when(adminShopAccessService.resolveScope(100)).thenReturn(AdminDataScope.SHOP);
        when(adminShopAccessService.listAccessibleShopIds(100)).thenReturn(Collections.singleton(1));

        User u = new User();
        u.setId(10);
        u.setPoints(20);
        when(userService.getUserByOpenid("test_openid_10")).thenReturn(u);
        when(userService.addPoints(10, 100)).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("openid", "test_openid_10");
        body.put("points", 100);

        R res = adminOrderController.addPoints(body);
        assertEquals(0, res.get("code"));
        assertEquals(120, res.get("points"));
    }

    // ==================== Stage 2: Cross-Store & Single-Store Co-existence Tests ====================

    @Test
    void testSingleStoreModeRejectsCrossShopBalanceCheckout() {
        // Configure Store 2 as single store mode (cross_shop_balance_enabled = false)
        com.lanf.entity.SystemConfig cfg = new com.lanf.entity.SystemConfig();
        cfg.setConfig_value("0");
        when(systemConfigMapper.selectByShopAndKey(eq(2), eq("member_balance_cross_shop_enabled"))).thenReturn(cfg);

        // User 10 has ¥0 at Store 2
        when(shopMemberWalletMapper.selectByUserAndShop(10, 2)).thenReturn(null);
        when(shopMemberWalletMapper.selectWalletsWithBalance(10)).thenReturn(Collections.singletonList(
                ShopMemberWallet.builder().user_id(10).shop_id(1).principal_balance(new BigDecimal("500.00")).gift_balance(BigDecimal.ZERO).build()
        ));

        // When checking available balance for Store 2
        BigDecimal store2Bal = shopMemberWalletService.getAvailableBalanceForShop(10, 2);
        assertEquals(0, store2Bal.compareTo(BigDecimal.ZERO));

        // Attempting to check out at Store 2
        User payer = new User();
        payer.setId(10);
        payer.setOpenid("test_user_10");
        payer.setPhone("13800138000");
        payer.setPrincipal_balance(new BigDecimal("500.00"));
        payer.setGift_balance(BigDecimal.ZERO);
        payer.setBalance(new BigDecimal("500.00"));

        when(userService.getUserByOpenid("test_user_10")).thenReturn(payer);

        Order o = new Order();
        o.setOrder_no("ORD_TEST_201");
        o.setShop_id(2);
        o.setSett_amount(100.0);
        o.setDiscount_amount(0.0);
        o.setService_fee(0.0);
        o.setTransac_status("unsettled");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(o);

        CashierCheckoutService cashierCheckoutService = new CashierCheckoutService();
        ReflectionTestUtils.setField(cashierCheckoutService, "orderService", orderService);
        ReflectionTestUtils.setField(cashierCheckoutService, "userService", userService);
        ReflectionTestUtils.setField(cashierCheckoutService, "shopMemberWalletService", shopMemberWalletService);
        com.lanf.payment.service.PaymentCapabilityService paymentCapabilityService = mock(com.lanf.payment.service.PaymentCapabilityService.class);
        when(paymentCapabilityService.isCashierPaymentMethodEnabled(eq(2), anyString())).thenReturn(true);
        com.lanf.payment.service.CashierCollectionIntentService collectionIntentService = mock(com.lanf.payment.service.CashierCollectionIntentService.class);
        com.lanf.payment.service.WechatJsapiPaymentService jsapiPaymentService = mock(com.lanf.payment.service.WechatJsapiPaymentService.class);
        when(jsapiPaymentService.prepareForAmountMutation(o)).thenReturn(o);
        ReflectionTestUtils.setField(cashierCheckoutService, "paymentCapabilityService", paymentCapabilityService);
        ReflectionTestUtils.setField(cashierCheckoutService, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(cashierCheckoutService, "wechatJsapiPaymentService", jsapiPaymentService);

        Map<String, Object> req = new HashMap<>();
        req.put("order_no", "ORD_TEST_201");
        req.put("payment_method", "余额支付");
        req.put("openid", "test_user_10");
        req.put("phone", "13800138000");
        req.put("allowSlaveOrderCheckout", true);

        R payRes = cashierCheckoutService.checkout(2, req);
        assertNotEquals(0, payRes.get("code"));
        assertTrue(payRes.get("msg").toString().contains("本店会员储值余额不足"));
    }

    @Test
    void testChainSharedModeAllowsCrossShopBalanceAndRecordsClearing() {
        // Configure Store 2 as chain mode (cross_shop_balance_enabled = true / default)
        when(systemConfigMapper.selectByShopAndKey(anyInt(), eq("member_balance_cross_shop_enabled"))).thenReturn(null);

        // User 10 has ¥30 at Store 2, and ¥100 at Store 1
        ShopMemberWallet walletShop2 = ShopMemberWallet.builder()
                .id(1L).user_id(10).shop_id(2)
                .principal_balance(new BigDecimal("30.00")).gift_balance(BigDecimal.ZERO).build();
        ShopMemberWallet walletShop1 = ShopMemberWallet.builder()
                .id(2L).user_id(10).shop_id(1)
                .principal_balance(new BigDecimal("100.00")).gift_balance(BigDecimal.ZERO).build();

        when(shopMemberWalletMapper.selectByUserAndShop(10, 2)).thenReturn(walletShop2);
        when(shopMemberWalletMapper.selectWalletsWithBalance(10)).thenReturn(Arrays.asList(walletShop2, walletShop1));

        // User consumes ¥80 at Store 2: Store 2 local ¥30, Store 1 cross-store ¥50
        boolean ok = shopMemberWalletService.deductAndClearBalance(10, 2, new BigDecimal("80.00"), BigDecimal.ZERO, "ORD_TEST_202");
        assertTrue(ok);

        // Verifies cross shop clearing record inserted
        verify(crossShopClearingMapper).insert(argThat(clearing ->
                clearing.getSource_shop_id() == 1 &&
                clearing.getConsume_shop_id() == 2 &&
                clearing.getTotal_amount().compareTo(new BigDecimal("50.00")) == 0
        ));
    }

    @Test
    void testCrossShopClearingReportCalculation() {
        // Mock cross-shop clearing summaries
        List<Map<String, Object>> mockSummaries = new ArrayList<>();
        Map<String, Object> row1 = new HashMap<>();
        row1.put("source_shop_id", 1);
        row1.put("consume_shop_id", 2);
        row1.put("total_amount", 50.00);
        row1.put("order_count", 1);
        mockSummaries.add(row1);

        when(crossShopClearingMapper.summarizeCrossShopClearing(eq(2), any(), any())).thenReturn(mockSummaries);
        when(crossShopClearingMapper.summarizeCrossShopClearing(eq(1), any(), any())).thenReturn(mockSummaries);

        // Store 2 perspective (consumed at 2, funded by 1 -> Inflow receivable +¥50)
        Map<String, Object> report2 = shopMemberWalletService.getCrossShopClearingReport(2, "2026-10-01", "2026-10-16");
        Map<String, Object> summary2 = (Map<String, Object>) report2.get("summary");
        assertEquals(new BigDecimal("50.00"), summary2.get("crossInflowAmount"));
        assertEquals(BigDecimal.ZERO, summary2.get("crossOutflowAmount"));
        assertEquals(new BigDecimal("50.00"), summary2.get("netSettlementAmount"));

        // Store 1 perspective (funded by 1, consumed at 2 -> Outflow payable -¥50)
        Map<String, Object> report1 = shopMemberWalletService.getCrossShopClearingReport(1, "2026-10-01", "2026-10-16");
        Map<String, Object> summary1 = (Map<String, Object>) report1.get("summary");
        assertEquals(BigDecimal.ZERO, summary1.get("crossInflowAmount"));
        assertEquals(new BigDecimal("50.00"), summary1.get("crossOutflowAmount"));
        assertEquals(new BigDecimal("-50.00"), summary1.get("netSettlementAmount"));
    }
}
