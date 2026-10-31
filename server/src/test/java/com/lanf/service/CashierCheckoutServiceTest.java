package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.entity.User;
import com.lanf.entity.PaymentLedger;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.service.PaymentRefundLedger;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import com.lanf.payment.mapper.WechatNativePaymentAttemptMapper;
import com.lanf.mapper.DailyCloseSnapshotMapper;
import com.lanf.entity.DailyCloseSnapshot;
import com.lanf.entity.Shop;
import com.lanf.entity.DailyStat;
import com.lanf.service.IShopService;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.IDailyStatService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierCheckoutServiceTest {

    private CashierCheckoutService service;
    private IOrderService orderService;
    private ITableService tableService;
    private IUserService userService;
    private PaymentCapabilityService capabilities;
    private UserCouponMapper userCouponMapper;
    private PaymentRefundLedger paymentRefundLedger;
    private CashierCollectionIntentService collectionIntentService;
    private PaymentSuccessHandler paymentSuccessHandler;
    private PaymentLedgerService paymentLedgerService;
    private WechatJsapiPaymentService wechatJsapiPaymentService;
    private Order order;
    private User payer;

    @BeforeEach
    void setUp() {
        service = new CashierCheckoutService();
        orderService = mock(IOrderService.class);
        tableService = mock(ITableService.class);
        userService = mock(IUserService.class);
        capabilities = mock(PaymentCapabilityService.class);
        userCouponMapper = mock(UserCouponMapper.class);
        paymentRefundLedger = mock(PaymentRefundLedger.class);
        collectionIntentService = mock(CashierCollectionIntentService.class);
        paymentSuccessHandler = mock(PaymentSuccessHandler.class);
        paymentLedgerService = mock(PaymentLedgerService.class);
        wechatJsapiPaymentService = mock(WechatJsapiPaymentService.class);
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "tableService", tableService);
        ReflectionTestUtils.setField(service, "userService", userService);
        ReflectionTestUtils.setField(service, "userCouponMapper", userCouponMapper);
        ReflectionTestUtils.setField(service, "paymentCapabilityService", capabilities);
        ReflectionTestUtils.setField(service, "paymentRefundLedger", paymentRefundLedger);
        ReflectionTestUtils.setField(
                service, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(service, "paymentSuccessHandler", paymentSuccessHandler);
        ReflectionTestUtils.setField(service, "paymentLedgerService", paymentLedgerService);
        ReflectionTestUtils.setField(service, "wechatJsapiPaymentService", wechatJsapiPaymentService);

        order = new Order();
        order.setId(10);
        order.setOrder_no("ORD-10");
        order.setShop_id(7);
        order.setTransac_status("unsettled");
        order.setDineInOrTakeOut("打包");
        order.setSett_amount(100d);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        order.setMember_phone("13800000000");
        when(wechatJsapiPaymentService.prepareForAmountMutation(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        payer = new User();
        payer.setId(3);
        payer.setOpenid("wx-openid");
        payer.setPhone("13800000000");
        payer.setPrincipal_balance(new BigDecimal("30.00"));
        payer.setGift_balance(new BigDecimal("20.00"));
        payer.setBalance(new BigDecimal("50.00"));
    }

    @Test
    void checkoutAndUnCheckout_useReadCommittedForFreshTableReconciliation() throws Exception {
        Transactional checkout = CashierCheckoutService.class
                .getMethod("checkout", Integer.class, Map.class)
                .getAnnotation(Transactional.class);
        Transactional unCheckout = CashierCheckoutService.class
                .getMethod("unCheckout", Integer.class, String.class)
                .getAnnotation(Transactional.class);

        assertNotNull(checkout);
        assertNotNull(unCheckout);
        assertEquals(Isolation.READ_COMMITTED, checkout.isolation());
        assertEquals(Isolation.READ_COMMITTED, unCheckout.isolation());
    }

    @Test
    void checkout_lastDineInOrder_marksTableAwaitingClear() {
        Table table = occupiedTable();
        prepareDineInCashCheckout(table, Collections.emptyList(), true);

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        assertEquals(2, table.getStatus());
        assertEquals("ORD-10", table.getOrder_no());
        assertEquals(100d, table.getAmount());
        assertNotNull(table.getOut_time());
        verify(tableService).updateById(table);
        verify(paymentSuccessHandler, never()).run(any(), anyDouble());
    }

    @Test
    void checkout_packingOrder_runsPaymentSuccessFulfillment() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        verify(paymentSuccessHandler).run(order, 100d);
    }

    @Test
    void checkout_pickupOrder_runsPaymentSuccessFulfillment() {
        order.setDineInOrTakeOut("自提");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        verify(paymentSuccessHandler).run(order, 100d);
    }

    @Test
    void checkout_waimaiOrder_runsPaymentSuccessFulfillment() {
        order.setDineInOrTakeOut("外卖");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        verify(paymentSuccessHandler).run(order, 100d);
    }

    @Test
    void checkout_withRemainingDineInOrder_keepsTableOccupiedAndRecalculatesAmount() {
        Table table = occupiedTable();
        Order remaining = new Order();
        remaining.setId(11);
        remaining.setOrder_no("ORD-11");
        remaining.setShop_id(7);
        remaining.setTable_number("A01");
        remaining.setTransac_status("unsettled");
        remaining.setSett_amount(60d);
        remaining.setDiscount_amount(10d);
        remaining.setService_fee(0d);
        prepareDineInCashCheckout(table, Collections.singletonList(remaining), true);

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        assertEquals(1, table.getStatus());
        assertEquals("ORD-11", table.getOrder_no());
        assertEquals(50d, table.getAmount());
        assertEquals(null, table.getOut_time());
    }

    @Test
    void checkout_legacyDineInValue_isNormalizedAndUpdatesTable() {
        Table table = occupiedTable();
        prepareDineInCashCheckout(table, Collections.emptyList(), true);
        order.setDineInOrTakeOut("\u936B\u509E\uE5E4");

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        assertEquals("堂食", order.getDineInOrTakeOut());
        assertEquals(2, table.getStatus());
    }

    @Test
    void checkout_tableWriteFailure_throwsForTransactionRollback() {
        Table table = occupiedTable();
        prepareDineInCashCheckout(table, Collections.emptyList(), false);

        assertThrows(IllegalStateException.class, () -> service.checkout(7, cashBody()));
    }

    @Test
    void unCheckout_dineInOrder_restoresOccupiedTableAndOutstandingAmount() {
        Table table = occupiedTable();
        table.setStatus(2);
        order.setDineInOrTakeOut("堂食");
        order.setTable_number("A01");
        order.setTransac_status("success");
        order.setPayment_method(PaymentChannelCatalog.NAME_BALANCE_PAY);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);
        when(tableService.updateById(table)).thenReturn(true);

        R result = service.unCheckout(7, "ORD-10");

        assertEquals(0, result.get("code"));
        assertEquals(1, table.getStatus());
        assertEquals("ORD-10", table.getOrder_no());
        assertEquals(100d, table.getAmount());
        assertEquals(null, table.getOut_time());
    }

    @Test
    void checkout_deductsOnlyCombinedBalancePartAndReturnsNormalizedSplit() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        User remaining = new User();
        remaining.setId(3);
        remaining.setBalance(new BigDecimal("40.00"));
        remaining.setPrincipal_balance(new BigDecimal("24.00"));
        remaining.setGift_balance(new BigDecimal("16.00"));
        when(userService.getById(3)).thenReturn(remaining);
        when(userService.subtractBalanceSplitIfEnough(
                eq(3), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_COMBINED);
        body.put("pay_amount_wechat", 90d);
        body.put("pay_amount_balance", 10d);
        body.put("openid", "wx-openid");
        body.put("member_phone", "13800000000");

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        assertEquals(false, result.get("idempotent"));
        @SuppressWarnings("unchecked")
        Map<String, Object> split = (Map<String, Object>) result.get("split");
        assertEquals(90d, split.get("wechat"));
        assertEquals(10d, split.get("balance"));
        verify(collectionIntentService).complete(7, "ORD-10", null);
        assertEquals(6d, split.get("balance_principal"));
        assertEquals(4d, split.get("balance_gift"));
        assertEquals(new BigDecimal("40.00"), result.get("remaining_balance"));
        verify(userService).subtractBalanceSplitIfEnough(
                3, new BigDecimal("6.00"), new BigDecimal("4.00"));
    }

    @Test
    void checkoutRejectsAnotherCollectionSessionBeforeWalletMutation() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        doThrow(new IllegalStateException("该订单正在其他窗口收款"))
                .when(collectionIntentService)
                .validateCheckout(7, "ORD-10", "session-other", 9000, 0);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_COMBINED);
        body.put("pay_amount_wechat", 90d);
        body.put("pay_amount_balance", 10d);
        body.put("openid", "wx-openid");
        body.put("member_phone", "13800000000");
        body.put("collection_session_id", "session-other");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(orderService, never()).updateById(any());
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
    }

    @Test
    void checkout_isIdempotentForAlreadySettledSameMethodAndNeverDeductsAgain() {
        order.setTransac_status("success");
        order.setPayment_method(PaymentChannelCatalog.NAME_BALANCE_PAY);
        order.setPay_openid("wx-openid");
        order.setPay_amount_balance(6d);
        order.setPay_amount_gift(4d);
        order.setBalance_pay_principal(6d);
        order.setBalance_pay_gift_wallet(4d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "wx-openid");

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        assertEquals(true, result.get("idempotent"));
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void checkout_rejectsMismatchedMemberIdentityBeforeWalletMutation() {
        payer.setPhone("13900000000");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "wx-openid");
        body.put("member_phone", "13800000000");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
    }

    @Test
    void checkout_fallsBackToLockedOrderOpenidWhenBodyOmitsOpenid() {
        order.setOpenid("wx-openid");
        payer.setPrincipal_balance(new BigDecimal("60.00"));
        payer.setGift_balance(new BigDecimal("40.00"));
        payer.setBalance(new BigDecimal("100.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.getById(3)).thenReturn(payer);
        when(userService.subtractBalanceSplitIfEnough(
                eq(3), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        verify(userService).getUserByOpenid("wx-openid");
        verify(userService).subtractBalanceSplitIfEnough(
                3, new BigDecimal("60.00"), new BigDecimal("40.00"));
    }

    @Test
    void checkout_fallsBackToLockedPayOpenidWhenBodyOmitsOpenid() {
        order.setPay_openid("wx-openid");
        payer.setPrincipal_balance(new BigDecimal("60.00"));
        payer.setGift_balance(new BigDecimal("40.00"));
        payer.setBalance(new BigDecimal("100.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.getById(3)).thenReturn(payer);
        when(userService.subtractBalanceSplitIfEnough(
                eq(3), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        verify(userService).getUserByOpenid("wx-openid");
    }

    @Test
    void checkout_rejectsSubmittedOpenidThatDiffersFromLockedOrder() {
        order.setOpenid("locked-openid");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "different-openid");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(userService, never()).getUserByOpenid(any());
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
    }

    @Test
    void checkout_rejectsMemberAccountWithoutBoundPhone() {
        payer.setPhone(" ");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "wx-openid");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
    }

    @Test
    void checkout_rejectsInvalidCombinedCashChangeBeforeBalanceDeduction() {
        payer.setPrincipal_balance(new BigDecimal("60.00"));
        payer.setGift_balance(new BigDecimal("40.00"));
        payer.setBalance(new BigDecimal("100.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.subtractBalanceSplitIfEnough(
                eq(3), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_COMBINED);
        body.put("pay_amount_cash", 50d);
        body.put("pay_amount_balance", 50d);
        body.put("openid", "wx-openid");
        body.put("checkout_cash_tender", 120d);

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        assertEquals("unsettled", order.getTransac_status());
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void checkout_validatesCombinedWechatAgainstCashierChannelSwitch() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.ONLINE_COMBINED)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.CASH)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.ONLINE_WECHAT)).thenReturn(false);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_COMBINED);
        body.put("pay_amount_cash", 50d);
        body.put("pay_amount_wechat", 50d);
        body.put("checkout_cash_tender", 50d);

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        assertEquals("unsettled", order.getTransac_status());
        verify(capabilities).isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.CASH);
        verify(capabilities).isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.ONLINE_WECHAT);
        verify(capabilities, never()).isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR);
        verify(orderService, never()).updateById(any());
    }

    @Test
    void checkout_acceptsOfflineWechatCodeWithConfirmedCollection() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR)).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.OFFLINE_WECHAT_QR);
        body.put("collection_session_id", "confirmed-session");

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        verify(collectionIntentService).validateCheckout(
                7, "ORD-10", "confirmed-session", 10000, 0, false);
        verify(collectionIntentService).complete(
                7, "ORD-10", "confirmed-session");
    }

    @Test
    void checkout_acceptsOfflineWechatAutoPaymentMethod() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR)).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.NAME_WECHAT_QR_AUTO);
        body.put("collection_session_id", "confirmed-session-auto");

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        assertEquals("微信收款码自动", order.getPayment_method());
        assertEquals("微信收款码自动", result.get("payment_method"));
        assertEquals("offline_wechat_qr", result.get("payment_channel_code"));
        verify(collectionIntentService).validateCheckout(
                7, "ORD-10", "confirmed-session-auto", 10000, 0, false);
        verify(collectionIntentService).complete(
                7, "ORD-10", "confirmed-session-auto");
    }

    @SuppressWarnings("unchecked")
    @Test
    void checkout_offlineWechatQr_persistsDedicatedLedgerChannel() {
        PaymentLedgerService ledgerService = mock(PaymentLedgerService.class);
        ReflectionTestUtils.setField(service, "paymentLedgerService", ledgerService);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR)).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.OFFLINE_WECHAT_QR);
        body.put("collection_session_id", "confirmed-session");

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<Map<String, Integer>> amounts = ArgumentCaptor.forClass(Map.class);
        verify(ledgerService).recordSettlement(
                eq(order), any(), any(), any(), any(), any(), any(), amounts.capture(), any());
        assertEquals(Integer.valueOf(10000),
                amounts.getValue().get(PaymentLedger.CHANNEL_WECHAT_QR));
        assertFalse(amounts.getValue().containsKey(PaymentLedger.CHANNEL_WECHAT));
    }

    @Test
    void checkout_rejectsFullBalanceWhenOrderHasDiscount() {
        order.setDiscount_amount(10d);
        payer.setPrincipal_balance(new BigDecimal("90.00"));
        payer.setGift_balance(BigDecimal.ZERO);
        payer.setBalance(new BigDecimal("90.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "wx-openid");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void checkout_rejectsFullBalanceWhenCouponIsBoundToOrder() {
        payer.setPrincipal_balance(new BigDecimal("100.00"));
        payer.setGift_balance(BigDecimal.ZERO);
        payer.setBalance(new BigDecimal("100.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userCouponMapper.selectCount(any(Wrapper.class))).thenReturn(1);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "wx-openid");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void checkout_allowsPartialBalanceInTrueCombinedPaymentDespiteOrderDiscount() {
        order.setDiscount_amount(10d);
        payer.setPrincipal_balance(new BigDecimal("100.00"));
        payer.setGift_balance(BigDecimal.ZERO);
        payer.setBalance(new BigDecimal("100.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.getById(3)).thenReturn(payer);
        when(userService.subtractBalanceSplitIfEnough(
                eq(3), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_COMBINED);
        body.put("pay_amount_cash", 60d);
        body.put("pay_amount_balance", 30d);
        body.put("openid", "wx-openid");
        body.put("checkout_cash_tender", 60d);

        R result = service.checkout(7, body);

        assertEquals(0, result.get("code"));
        verify(userService).subtractBalanceSplitIfEnough(
                3, new BigDecimal("30.00"), BigDecimal.ZERO.setScale(2));
    }

    @Test
    void checkout_throwsAfterWalletDeductionWhenOrderWriteFailsSoTransactionRollsBack() {
        payer.setPrincipal_balance(new BigDecimal("60.00"));
        payer.setGift_balance(new BigDecimal("40.00"));
        payer.setBalance(new BigDecimal("100.00"));
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(false);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.subtractBalanceSplitIfEnough(
                eq(3), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.ONLINE_BALANCE);
        body.put("openid", "wx-openid");

        assertThrows(IllegalStateException.class, () -> service.checkout(7, body));
    }

    @Test
    void unCheckout_restoresStoredPrincipalAndGiftExactlyOnce() {
        order.setTransac_status("success");
        order.setPayment_method(PaymentChannelCatalog.NAME_COMBINED_PAY);
        order.setPay_openid("wx-openid");
        order.setBalance_pay_principal(6d);
        order.setBalance_pay_gift_wallet(4d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.addBalanceAndGift(
                3, new BigDecimal("6.00"), new BigDecimal("4.00"))).thenReturn(true);

        R first = service.unCheckout(7, "ORD-10");
        R second = service.unCheckout(7, "ORD-10");

        assertEquals(0, first.get("code"));
        assertEquals(10d, first.get("restored_balance"));
        assertEquals(true, second.get("alreadyUnChecked"));
        verify(userService).addBalanceAndGift(
                3, new BigDecimal("6.00"), new BigDecimal("4.00"));
    }

    @Test
    void refundWalletComponent_restoresPrincipalAndGiftAndIsIdempotent() {
        order.setTransac_status("success");
        order.setPay_openid("wx-openid");
        order.setBalance_pay_principal(6d);
        order.setBalance_pay_gift_wallet(4d);
        order.setPay_amount_balance(6d);
        order.setPay_amount_gift(4d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.addBalanceAndGift(
                3, new BigDecimal("6.00"), new BigDecimal("4.00"))).thenReturn(true);
        PaymentLedger principalPayment = PaymentLedger.builder().id(601L)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL).amount_fen(600)
                .status(PaymentLedger.STATUS_SUCCEEDED).build();
        PaymentLedger giftPayment = PaymentLedger.builder().id(602L)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_GIFT).amount_fen(400)
                .status(PaymentLedger.STATUS_SUCCEEDED).build();
        when(paymentLedgerService.listByOrder(7, "ORD-10"))
                .thenReturn(java.util.Arrays.asList(principalPayment, giftPayment));

        R first = service.refundWalletComponent("ORD-10", new HashMap<>());
        R replay = service.refundWalletComponent("ORD-10", new HashMap<>());

        assertEquals(10d, first.get("refund_amount"));
        assertEquals(true, replay.get("alreadyRefunded"));
        verify(userService).addBalanceAndGift(
                3, new BigDecimal("6.00"), new BigDecimal("4.00"));
        InOrder sequence = inOrder(paymentLedgerService, userService, orderService);
        sequence.verify(paymentLedgerService).recordRefund(
                eq(order), eq(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL), eq(600), isNull(), anyString(), anyString(), eq(601L), isNull());
        sequence.verify(paymentLedgerService).recordRefund(
                eq(order), eq(PaymentLedger.CHANNEL_GIFT), eq(400), isNull(), anyString(), anyString(), eq(602L), isNull());
        sequence.verify(userService).addBalanceAndGift(
                3, new BigDecimal("6.00"), new BigDecimal("4.00"));
        sequence.verify(orderService).updateById(order);
    }

    @Test
    void refundCashComponent_recordsLinkedRefundBeforeUpdatingOrder() {
        order.setTransac_status("success");
        order.setPay_amount_cash(100d);
        order.setRefund_amount(0d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        PaymentLedger cashPayment = PaymentLedger.builder().id(701L)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_CASH).amount_fen(10000)
                .status(PaymentLedger.STATUS_SUCCEEDED).build();
        when(paymentLedgerService.listByOrder(7, "ORD-10"))
                .thenReturn(Collections.singletonList(cashPayment));
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("refundAmount", 25d);
        body.put("request_id", "CASH-REF-1");

        R result = service.refundCashComponent(7, body);

        assertEquals(0, result.get("code"));
        InOrder sequence = inOrder(paymentLedgerService, orderService);
        sequence.verify(paymentLedgerService).recordRefund(
                order, PaymentLedger.CHANNEL_CASH, 2500, null,
                "CASH-REF-1", java.time.LocalDate.now().toString(), 701L, null);
        sequence.verify(orderService).updateById(order);
    }

    @Test
    void checkout_rejectsUnknownPaymentAliasBeforeWritingLedger() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", "会员余额");

        R result = service.checkout(7, body);

        assertEquals(500, result.get("code"));
        verify(userService, never()).subtractBalanceSplitIfEnough(
                any(), any(BigDecimal.class), any(BigDecimal.class));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void unCheckout_rejectsExternalFundsBeforeWalletRestore() {
        order.setTransac_status("success");
        order.setPayment_method(PaymentChannelCatalog.NAME_COMBINED_PAY);
        order.setBalance_pay_principal(20d);
        order.setPay_amount_balance(20d);
        order.setPay_amount_cash(80d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        R result = service.unCheckout(7, "ORD-10");

        assertEquals(500, result.get("code"));
        verify(userService, never()).addBalanceAndGift(
                any(), any(BigDecimal.class), any(BigDecimal.class));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void unCheckout_rejectsSingleOfflineQrFunds() {
        order.setTransac_status("success");
        order.setPayment_method(PaymentChannelCatalog.NAME_WECHAT_QR);
        order.setPay_amount_wechat(100d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        R result = service.unCheckout(7, "ORD-10");

        assertEquals(500, result.get("code"));
        verify(orderService, never()).updateById(any());
    }

    @Test
    void wechatRefundNotification_usesDurableLedgerAndAppliesOnlyOnce() {
        order.setTransac_status("success");
        order.setPay_amount_wechat(100d);
        order.setRefund_amount(0d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(paymentRefundLedger.beginCallback(7, "ORD-10", "RF-ONE", 2500))
                .thenReturn(true, false);

        R first = service.applyWechatRefundNotification("ORD-10", "RF-ONE", 2500);
        R replay = service.applyWechatRefundNotification("ORD-10", "RF-ONE", 2500);

        assertEquals(0, first.get("code"));
        assertEquals(2500, first.get("applied_fen"));
        assertEquals(true, replay.get("idempotent"));
        assertEquals(25d, order.getRefund_amount());
        assertEquals(75d, order.getPay_amount_wechat());
        verify(orderService).updateById(order);
        verify(paymentRefundLedger).markSuccess("RF-ONE", 2500);
    }

    private Table occupiedTable() {
        Table table = new Table();
        table.setId(20);
        table.setShop_id(7);
        table.setNumber("A01");
        table.setStatus(1);
        table.setOrder_no("ORD-10");
        table.setAmount(100d);
        return table;
    }

    private void prepareDineInCashCheckout(
            Table table, List<Order> remaining, boolean tableUpdateSucceeds) {
        order.setDineInOrTakeOut("堂食");
        order.setTable_number("A01");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(orderService.list(any(Wrapper.class))).thenReturn(remaining);
        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);
        when(tableService.updateById(table)).thenReturn(tableUpdateSucceeds);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
    }

    @Test
    void checkout_recordsPaymentLedger_whenLedgerServicePresent() {
        PaymentLedgerService ledgerService = mock(PaymentLedgerService.class);
        ReflectionTestUtils.setField(service, "paymentLedgerService", ledgerService);

        order.setDineInOrTakeOut("打包");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        Map<String, Object> body = cashBody();
        body.put("request_id", "REQ-CHECKOUT-10");
        body.put("terminal_id", "TERM-01");
        body.put("operator_id", 88);

        R res = service.checkout(7, body);
        assertEquals(0, res.get("code"));

        verify(ledgerService).recordSettlement(
                eq(order),
                eq(88),
                eq("REQ-CHECKOUT-10"),
                eq("TERM-01"),
                any(),
                any(),
                any(),
                any(),
                any()
        );
    }

    @Test
    void checkout_writesAuthoritativeLedgerBeforeOrderSuccessState() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        R result = service.checkout(7, cashBody());

        assertEquals(0, result.get("code"));
        org.mockito.InOrder sequence = org.mockito.Mockito.inOrder(paymentLedgerService, orderService);
        sequence.verify(paymentLedgerService).recordSettlement(
                eq(order), any(), any(), any(), any(), any(), any(), any(), any());
        sequence.verify(orderService).updateById(order);
    }

    @Test
    void checkout_ledgerFailureNeverMarksOrderPaid() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        doThrow(new IllegalStateException("ledger unavailable")).when(paymentLedgerService)
                .recordSettlement(any(), any(), any(), any(), any(), any(), any(), any(), any());

        assertThrows(IllegalStateException.class, () -> service.checkout(7, cashBody()));

        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void checkout_paymentCallbackWinsBeforeManualLedgerWrite() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(wechatJsapiPaymentService.prepareForAmountMutation(order))
                .thenThrow(new IllegalStateException("订单已被微信支付"));

        assertThrows(IllegalStateException.class, () -> service.checkout(7, cashBody()));

        verify(paymentLedgerService, never()).recordSettlement(
                any(), any(), any(), any(), any(), any(), any(), any(), any());
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void unCheckout_recordsReversal_whenLedgerServicePresent() {
        PaymentLedgerService ledgerService = mock(PaymentLedgerService.class);
        ReflectionTestUtils.setField(service, "paymentLedgerService", ledgerService);

        order.setTransac_status("success");
        order.setDineInOrTakeOut("打包");
        order.setBalance_pay_principal(30d);
        order.setBalance_pay_gift_wallet(20d);
        order.setPay_openid("wx-openid");

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(userService.getUserByOpenid("wx-openid")).thenReturn(payer);
        when(userService.addBalanceAndGift(eq(3), any(), any())).thenReturn(true);

        R res = service.unCheckout(7, "ORD-10");
        assertEquals(0, res.get("code"));

        verify(ledgerService).recordReversal(
                eq(order),
                isNull(),
                any(),
                isNull(),
                eq("反结账全额冲正")
        );
    }

    @Test
    void checkout_recordsCashMovement_whenDrawerSessionServicePresent() {
        PaymentLedgerService ledgerService = mock(PaymentLedgerService.class);
        DrawerSessionService drawerService = mock(DrawerSessionService.class);
        ReflectionTestUtils.setField(service, "paymentLedgerService", ledgerService);
        ReflectionTestUtils.setField(service, "drawerSessionService", drawerService);

        order.setDineInOrTakeOut("打包");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        Map<String, Object> body = cashBody();
        body.put("request_id", "REQ-CHECKOUT-CASH");
        body.put("terminal_id", "TERM-01");
        body.put("operator_id", 88);

        PaymentLedger pl = PaymentLedger.builder().channel(PaymentLedger.CHANNEL_CASH).amount_fen(10000).build();
        when(ledgerService.recordSettlement(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(Collections.singletonList(pl));

        R res = service.checkout(7, body);
        assertEquals(0, res.get("code"));

        verify(drawerService).recordCashSale(
                eq(7),
                eq("TERM-01"),
                isNull(),
                eq(order),
                eq(pl),
                eq(10000),
                eq(88)
        );
    }

    @Test
    void checkout_whenOrderIsMergedSlaveOrder_shouldRejectIfNotTableCheckout() {
        order.setMaster_order_no("ORD-MASTER");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        R res = service.checkout(7, cashBody());

        assertEquals(500, res.get("code"));
        assertEquals("该订单为并台从单，不支持单独结账，请通过主桌统一结账", res.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void checkout_whenOrderIsMergedSlaveOrder_shouldAllowIfTableCheckout() {
        order.setMaster_order_no("ORD-MASTER");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        Map<String, Object> body = cashBody();
        body.put("allowSlaveOrderCheckout", true);

        R res = service.checkout(7, body);

        assertEquals(0, res.get("code"));
        verify(orderService).updateById(org.mockito.ArgumentMatchers.argThat(o -> "success".equals(o.getTransac_status())));
    }

    @Test
    void checkout_whenOrderHasUnsettledSlaveOrders_shouldRejectIfNotTableCheckout() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.count(any(Wrapper.class))).thenReturn(1);

        R res = service.checkout(7, cashBody());

        assertEquals(500, res.get("code"));
        assertEquals("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账", res.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void checkout_whenActiveWechatNativeAttemptExists_shouldRejectWith40935() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        WechatNativePaymentAttemptMapper nativeMapper = mock(WechatNativePaymentAttemptMapper.class);
        WechatNativePaymentAttemptEntity attempt = new WechatNativePaymentAttemptEntity();
        attempt.setStatus("ACTIVE");
        attempt.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(nativeMapper.selectOne(any(Wrapper.class))).thenReturn(attempt);
        ReflectionTestUtils.setField(service, "nativeAttemptMapper", nativeMapper);

        R res = service.checkout(7, cashBody());
        assertEquals(40935, res.get("code"));
        assertEquals("该订单正在进行微信扫码支付中，请先在收银端关闭支付二维码或确认顾客未付款", res.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void checkout_whenShiftRequiredAndNoDrawerSession_shouldRejectWith4002() {
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(capabilities.isCashierPaymentMethodEnabled(eq(7), any())).thenReturn(true);

        IShopService mockShopService = mock(IShopService.class);
        Shop shop = new Shop();
        shop.setId(7);
        shop.setShift_required(1);
        when(mockShopService.getById(7)).thenReturn(shop);
        ReflectionTestUtils.setField(service, "shopService", mockShopService);

        DrawerSessionService mockDrawerService = mock(DrawerSessionService.class);
        when(mockDrawerService.getActiveSession(eq(7), any(), any())).thenReturn(null);
        ReflectionTestUtils.setField(service, "drawerSessionService", mockDrawerService);

        R res = service.checkout(7, cashBody());
        assertEquals(4002, res.get("code"));
        assertEquals("当前钱箱未开班，请先完成开班后再进行现金收银", res.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void unCheckout_whenDailyClosed_shouldRejectWith40936() {
        order.setTransac_status("success");
        order.setPay_time(new Date());
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        IShopService mockShopService = mock(IShopService.class);
        Shop shop = new Shop();
        shop.setId(7);
        shop.setSettle_time("04:00");
        when(mockShopService.getById(7)).thenReturn(shop);
        ReflectionTestUtils.setField(service, "shopService", mockShopService);

        DailyCloseSnapshotMapper snapshotMapper = mock(DailyCloseSnapshotMapper.class);
        when(snapshotMapper.selectCount(any(Wrapper.class))).thenReturn(1);
        ReflectionTestUtils.setField(service, "dailyCloseSnapshotMapper", snapshotMapper);

        R res = service.unCheckout(7, "ORD-10");
        assertEquals(40936, res.get("code"));
        assertEquals("该订单所属营业日已完成日结封账，禁止反结账", res.get("msg"));
        verify(orderService, never()).updateById(any(Order.class));
    }

    private static Map<String, Object> cashBody() {
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-10");
        body.put("payment_method", PaymentChannelCatalog.CASH);
        return body;
    }
}
