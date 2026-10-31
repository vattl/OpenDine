package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.payment.support.PaymentSettlementLedgerHelper;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.entity.PaymentLedger;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatPaymentSuccessServiceTest {

    private final IOrderService orderService = mock(IOrderService.class);
    private final OrderPaymentBridge bridge = mock(OrderPaymentBridge.class);
    private final PaymentSettlementLedgerHelper ledgerHelper = mock(PaymentSettlementLedgerHelper.class);
    private final WechatMerchantKeyStore merchantKeyStore = mock(WechatMerchantKeyStore.class);
    private WechatPaymentSuccessService service;

    @BeforeEach
    void setUp() {
        service = new WechatPaymentSuccessService();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "orderPaymentBridge", bridge);
        ReflectionTestUtils.setField(service, "paymentNotifyState", new PaymentNotifyState());
        ReflectionTestUtils.setField(service, "paymentSettlementLedgerHelper", ledgerHelper);
        ReflectionTestUtils.setField(service, "merchantKeyStore", merchantKeyStore);
        when(merchantKeyStore.resolveForPay(7, "1", null)).thenReturn(boundMerchant(7));
        when(ledgerHelper.recordAuthoritativePayment(any(Order.class), any(), any(), any()))
                .thenReturn(Collections.singletonList(PaymentLedger.builder().id(1L).build()));
    }

    @Test
    void rejectsAmountMismatchBeforeChangingOrder() {
        Order order = unsettledOrder();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);

        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", payment("NATIVE", 999), "1", 1250);

        assertFalse(result.success);
        assertEquals("AMOUNT_MISMATCH", result.code);
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void appliesNativePaymentOnceAndKeepsRetryIdempotent() {
        Order order = unsettledOrder();
        Order paid = unsettledOrder();
        paid.setTransac_status("success");
        paid.setTransaction_id("WX-TX-1");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order, paid);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        WechatPaymentSuccessService.ApplyResult first = service.apply(
                "ORDER-1", "ORDER-1_123", payment("NATIVE", 1250), "1", 1250);
        WechatPaymentSuccessService.ApplyResult retry = service.apply(
                "ORDER-1", "ORDER-1_123", payment("NATIVE", 1250), "1", 1250);

        assertTrue(first.success);
        assertFalse(first.alreadyPaid);
        assertTrue(retry.success);
        assertTrue(retry.alreadyPaid);
        verify(orderService).updateById(any(Order.class));
        verify(bridge).runPostPaymentSuccessSideEffects(any(Order.class), org.mockito.ArgumentMatchers.eq(12.5d));
    }

    @Test
    void legacyJsapiCallbackCannotConvertUnderpaymentIntoImplicitDiscount() {
        Order order = unsettledOrder();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);

        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", payment("JSAPI", 1000), "1", null);

        assertFalse(result.success);
        assertEquals("AMOUNT_MISMATCH", result.code);
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void trackedAttemptCannotSettleWhenOrderAmountChangedAfterPrepay() {
        Order order = unsettledOrder();
        order.setSett_amount(10d);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);

        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", payment("JSAPI", 1250), "1", 1250, 7);

        assertFalse(result.success);
        assertEquals("AMOUNT_MISMATCH", result.code);
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void legacyCallbackStillSettlesWhenAmountExactlyMatchesCurrentPayable() {
        Order order = unsettledOrder();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);

        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", payment("JSAPI", 1250), "1", null);

        assertTrue(result.success);
        assertFalse(result.alreadyPaid);
        verify(orderService).updateById(order);
    }

    @Test
    void differentSuccessfulWechatTransactionIsNotAnIdempotentRetry() {
        Order paid = unsettledOrder();
        paid.setTransac_status("success");
        paid.setTransaction_id("WX-TX-ORIGINAL");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(paid);

        Map<String, Object> duplicatePayment = payment("JSAPI", 1250);
        duplicatePayment.put("out_trade_no", "ORDER-1_456");
        duplicatePayment.put("transaction_id", "WX-TX-DUPLICATE");
        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_456", duplicatePayment, "1", 1250);

        assertFalse(result.success);
        assertEquals("DUPLICATE_PAYMENT", result.code);
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void authoritativeLedgerIsWrittenBeforeOrderBecomesPaid() {
        Order order = unsettledOrder();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);

        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", payment("JSAPI", 1250), "1", 1250, 7);

        assertTrue(result.success);
        org.mockito.InOrder sequence = inOrder(ledgerHelper, orderService);
        sequence.verify(ledgerHelper).recordAuthoritativePayment(
                any(Order.class), any(), any(), org.mockito.ArgumentMatchers.eq("WECHAT_WX-TX-1"));
        sequence.verify(orderService).updateById(order);
    }

    @Test
    void ledgerFailurePreventsOrderFromBeingMarkedPaid() {
        Order order = unsettledOrder();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        doThrow(new IllegalStateException("ledger unavailable"))
                .when(ledgerHelper).recordAuthoritativePayment(any(Order.class), any(), any(), any());

        assertThrows(IllegalStateException.class, () -> service.apply(
                "ORDER-1", "ORDER-1_123", payment("JSAPI", 1250), "1", 1250, 7));

        verify(orderService, never()).updateById(any(Order.class));
        verify(bridge, never()).runPostPaymentSuccessSideEffects(any(), anyDouble());
    }

    @Test
    void rejectsCallbackWhenMerchantIdentityFieldsAreMissing() {
        doReturn(Collections.singletonList(PaymentLedger.builder().id(1L).build()))
                .when(ledgerHelper).recordAuthoritativePayment(any(Order.class), any(), any(), any());
        Order order = unsettledOrder();
        order.setMerchant_config_id(9L);
        order.setMerchant_config_version(2);
        WechatMerchantKeyStore keyStore = mock(WechatMerchantKeyStore.class);
        WechatMerchantKeyStore.ResolvedMerchant merchant = boundMerchant(7);
        when(keyStore.resolveBound(9L, 2, 7)).thenReturn(merchant);
        ReflectionTestUtils.setField(service, "merchantKeyStore", keyStore);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);

        Map<String, Object> callback = payment("JSAPI", 1250);
        callback.remove("mchid");
        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", callback, "1", 1250, 7);

        assertFalse(result.success);
        assertEquals("MCH_ID_MISSING", result.code);
        verify(orderService, never()).updateById(any(Order.class));
    }

    @Test
    void rejectsBoundMerchantFromAnotherShop() {
        doReturn(Collections.singletonList(PaymentLedger.builder().id(1L).build()))
                .when(ledgerHelper).recordAuthoritativePayment(any(Order.class), any(), any(), any());
        Order order = unsettledOrder();
        order.setMerchant_config_id(9L);
        order.setMerchant_config_version(2);
        WechatMerchantKeyStore keyStore = mock(WechatMerchantKeyStore.class);
        when(keyStore.resolveBound(9L, 2, 7)).thenReturn(boundMerchant(8));
        ReflectionTestUtils.setField(service, "merchantKeyStore", keyStore);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);

        WechatPaymentSuccessService.ApplyResult result = service.apply(
                "ORDER-1", "ORDER-1_123", payment("JSAPI", 1250), "1", 1250, 7);

        assertFalse(result.success);
        assertEquals("MERCHANT_SHOP_MISMATCH", result.code);
        verify(orderService, never()).updateById(any(Order.class));
    }

    private static Order unsettledOrder() {
        Order order = new Order();
        order.setId(10);
        order.setOrder_no("ORDER-1");
        order.setShop_id(7);
        order.setSett_amount(12.5d);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        order.setTransac_status("unsettled");
        return order;
    }

    private static Map<String, Object> payment(String tradeType, int total) {
        Map<String, Object> payment = new HashMap<>();
        payment.put("out_trade_no", "ORDER-1_123");
        payment.put("transaction_id", "WX-TX-1");
        payment.put("trade_state", "SUCCESS");
        payment.put("trade_type", tradeType);
        payment.put("mchid", "MCH-7");
        payment.put("appid", "APP-7");
        payment.put("success_time", "2026-10-15T12:00:00+08:00");
        Map<String, Object> amount = new HashMap<>();
        amount.put("total", total);
        payment.put("amount", amount);
        return payment;
    }

    private static WechatMerchantKeyStore.ResolvedMerchant boundMerchant(int shopId) {
        WechatMerchantKeyStore.ResolvedMerchant merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.dbConfigId = 9L;
        merchant.dbConfigVersion = 2;
        merchant.dbShopId = shopId;
        merchant.mchId = "MCH-7";
        merchant.appId = "APP-7";
        return merchant;
    }
}
