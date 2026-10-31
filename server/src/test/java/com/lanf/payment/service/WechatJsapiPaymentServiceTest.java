package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatNativeApiClient;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.entity.WechatJsapiPaymentAttemptEntity;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import com.lanf.payment.mapper.WechatJsapiPaymentAttemptMapper;
import com.lanf.payment.mapper.WechatNativePaymentAttemptMapper;
import com.lanf.payment.settlement.PaymentSettlementService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatJsapiPaymentServiceTest {
    private final IOrderService orderService = mock(IOrderService.class);
    private final WechatJsapiPaymentAttemptMapper attemptMapper = mock(WechatJsapiPaymentAttemptMapper.class);
    private final WechatNativePaymentAttemptMapper nativeAttemptMapper = mock(WechatNativePaymentAttemptMapper.class);
    private final WechatNativeApiClient apiClient = mock(WechatNativeApiClient.class);
    private final PaymentSettlementService settlementService = mock(PaymentSettlementService.class);
    private final WechatPaymentSuccessService successService = mock(WechatPaymentSuccessService.class);
    private final WechatMerchantKeyStore merchantKeyStore = mock(WechatMerchantKeyStore.class);
    private WechatJsapiPaymentService service;

    @BeforeEach
    void setUp() {
        service = new WechatJsapiPaymentService();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "attemptMapper", attemptMapper);
        ReflectionTestUtils.setField(service, "nativeAttemptMapper", nativeAttemptMapper);
        ReflectionTestUtils.setField(service, "apiClient", apiClient);
        ReflectionTestUtils.setField(service, "settlementService", settlementService);
        ReflectionTestUtils.setField(service, "successService", successService);
        ReflectionTestUtils.setField(service, "merchantKeyStore", merchantKeyStore);
    }

    @Test
    void firstRequestCreatesTrackedAttemptWithServerCalculatedAmount() {
        Order order = order();
        WechatMerchantKeyStore.ResolvedMerchant merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.dbConfigId = 9L;
        merchant.dbConfigVersion = 3;
        merchant.merchantKey = "default";
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(settlementService.settle(order, null, "OPENID-1", true))
                .thenReturn(R.ok().put("paidYuan", 12.5d).put("merchantId", "1"));
        when(merchantKeyStore.resolveForPay(7, "1", null)).thenReturn(merchant);
        when(apiClient.createJsapi(eq(7), eq("1"), eq(9L), eq(3), anyString(), eq(1250),
                eq("OPENID-1"), anyString(), any(Date.class)))
                .thenReturn(new WechatNativeApiClient.JsapiCreateResult(
                        "PREPAY-NEW", Collections.singletonMap("package", "prepay_id=PREPAY-NEW")));

        R result = service.create("ORDER-1", "OPENID-1", null);

        assertEquals(0, result.get("code"));
        assertEquals(1250, result.get("amountFen"));
        assertEquals(Boolean.FALSE, result.get("reused"));
        verify(attemptMapper).insert(any(WechatJsapiPaymentAttemptEntity.class));
        verify(apiClient).createJsapi(eq(7), eq("1"), eq(9L), eq(3), anyString(), eq(1250),
                eq("OPENID-1"), anyString(), any(Date.class));
    }

    @Test
    void reusesSameActiveAttemptInsteadOfCreatingAnotherWechatTransaction() {
        Order order = order();
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(settlementService.settle(order, null, "OPENID-1", true))
                .thenReturn(R.ok().put("paidYuan", 12.5d).put("merchantId", "1"));
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(apiClient.buildJsapiPayParams(anyInt(), eq("1"), eq(9L), eq(3), eq("PREPAY-1")))
                .thenReturn(Collections.singletonMap("package", "prepay_id=PREPAY-1"));

        R result = service.create("ORDER-1", "OPENID-1", null);

        assertEquals(0, result.get("code"));
        assertEquals(Boolean.TRUE, result.get("reused"));
        assertEquals("OUT-1", result.get("outTradeNo"));
        verify(apiClient, never()).createJsapi(anyInt(), anyString(), any(), any(), anyString(),
                anyInt(), anyString(), anyString(), any(Date.class));
    }

    @Test
    void changedAmountClosesOldAttemptBeforeCreatingNewWechatTransaction() {
        Order order = order();
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        WechatNativeApiClient.QueryResult notPay = new WechatNativeApiClient.QueryResult();
        notPay.tradeState = "NOTPAY";
        WechatMerchantKeyStore.ResolvedMerchant merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.dbConfigId = 9L; merchant.dbConfigVersion = 3; merchant.merchantKey = "default";
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        when(settlementService.settle(order, null, "OPENID-1", true))
                .thenReturn(R.ok().put("paidYuan", 10d).put("merchantId", "1"));
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(apiClient.query(7, "1", 9L, 3, "OUT-1")).thenReturn(notPay);
        when(merchantKeyStore.resolveForPay(7, "1", null)).thenReturn(merchant);
        when(apiClient.createJsapi(eq(7), eq("1"), eq(9L), eq(3), anyString(), eq(1000),
                eq("OPENID-1"), anyString(), any(Date.class)))
                .thenReturn(new WechatNativeApiClient.JsapiCreateResult(
                        "PREPAY-NEW", Collections.singletonMap("package", "prepay_id=PREPAY-NEW")));

        R result = service.create("ORDER-1", "OPENID-1", null);

        assertEquals(0, result.get("code"));
        assertEquals(1000, result.get("amountFen"));
        verify(apiClient).close(7, "1", 9L, 3, "OUT-1");
        verify(apiClient).createJsapi(eq(7), eq("1"), eq(9L), eq(3), anyString(), eq(1000),
                eq("OPENID-1"), anyString(), any(Date.class));
    }

    @Test
    void paidAttemptWithDifferentPayerBecomesConflictAndCannotCreateAgain() {
        Order order = order();
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        attempt.setAmount_fen(1000);
        attempt.setStatus("UNKNOWN");
        WechatNativeApiClient.QueryResult paid = new WechatNativeApiClient.QueryResult();
        paid.tradeState = "SUCCESS";
        paid.tradeType = "JSAPI";
        paid.payerOpenid = "OTHER-OPENID";
        paid.transactionId = "WX-PAID";
        paid.total = 1000;
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(settlementService.settle(order, null, "OPENID-1", true))
                .thenReturn(R.ok().put("paidYuan", 10d).put("merchantId", "1"));
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(apiClient.query(7, "1", 9L, 3, "OUT-1")).thenReturn(paid);

        R result = service.create("ORDER-1", "OPENID-1", null);

        assertEquals(40932, result.get("code"));
        assertEquals("CONFLICT", attempt.getStatus());
        assertEquals("7:ORDER-1", attempt.getActive_key());
        verify(apiClient, never()).createJsapi(anyInt(), anyString(), any(), any(), anyString(),
                anyInt(), anyString(), anyString(), any(Date.class));
    }

    @Test
    void amountMutationClosesNotPayAttemptBeforeBusinessWriteCanContinue() {
        Order order = order();
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        WechatNativeApiClient.QueryResult query = new WechatNativeApiClient.QueryResult();
        query.tradeState = "NOTPAY";
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(apiClient.query(7, "1", 9L, 3, "OUT-1")).thenReturn(query);

        Order locked = service.prepareForAmountMutation(order);

        assertEquals(order, locked);
        verify(apiClient).close(7, "1", 9L, 3, "OUT-1");
        verify(attemptMapper).updateById(attempt);
        assertEquals("CLOSED", attempt.getStatus());
        assertEquals(null, attempt.getActive_key());
    }

    @Test
    void unknownWechatStateFailsClosedAndPreservesActiveKey() {
        Order order = order();
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(apiClient.query(7, "1", 9L, 3, "OUT-1")).thenThrow(new RuntimeException("timeout"));

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> service.prepareForAmountMutation(order));

        assertTrue(error.getMessage().contains("状态暂不确定"));
        assertEquals("UNKNOWN", attempt.getStatus());
        assertEquals("7:ORDER-1", attempt.getActive_key());
        verify(apiClient, never()).close(anyInt(), anyString(), any(), any(), anyString());
    }

    @Test
    void successfulWechatStateBlocksAmountMutationWithoutClosingPaidTransaction() {
        Order order = order();
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        WechatNativeApiClient.QueryResult query = new WechatNativeApiClient.QueryResult();
        query.tradeState = "SUCCESS";
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(apiClient.query(7, "1", 9L, 3, "OUT-1")).thenReturn(query);

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> service.prepareForAmountMutation(order));

        assertTrue(error.getMessage().contains("已被微信支付"));
        verify(apiClient, never()).close(anyInt(), anyString(), any(), any(), anyString());
        verify(successService, never()).apply(anyString(), anyString(), any(), anyString(), any(), any());
    }

    @Test
    void paymentThatWinsOrderLockBlocksRefundEvenAfterAttemptWasReleased() {
        Order paid = order();
        paid.setTransac_status("success");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(paid);

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> service.prepareForAmountMutation(order()));

        assertTrue(error.getMessage().contains("已被微信支付"));
        verify(attemptMapper, never()).selectOne(any(QueryWrapper.class));
        verify(apiClient, never()).query(anyInt(), anyString(), any(), any(), anyString());
        verify(apiClient, never()).close(anyInt(), anyString(), any(), any(), anyString());
    }

    @Test
    void paidConflictKeepsActiveKeyToPreventASecondPayment() {
        WechatJsapiPaymentAttemptEntity attempt = activeAttempt();
        WechatPaymentSuccessService.ApplyResult mismatch =
                WechatPaymentSuccessService.ApplyResult.error("AMOUNT_MISMATCH", "金额不匹配");

        service.markCallbackResult(attempt, Collections.singletonMap("transaction_id", "WX-PAID"), mismatch);

        assertEquals("CONFLICT", attempt.getStatus());
        assertEquals("7:ORDER-1", attempt.getActive_key());
        verify(attemptMapper).updateById(attempt);
    }

    @Test
    void amountMutationClosesActiveNativeAttemptWhenNotPay() {
        Order order = order();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        WechatNativePaymentAttemptEntity nativeAttempt = activeNativeAttempt();
        when(nativeAttemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(nativeAttempt);
        WechatNativeApiClient.QueryResult query = new WechatNativeApiClient.QueryResult();
        query.tradeState = "NOTPAY";
        when(apiClient.query(7, "1", 11L, 2, "OUT-NAT-1")).thenReturn(query);

        Order locked = service.prepareForAmountMutation(order);

        assertEquals(order, locked);
        verify(apiClient).close(7, "1", 11L, 2, "OUT-NAT-1");
        verify(nativeAttemptMapper).updateById(nativeAttempt);
        assertEquals("CLOSED", nativeAttempt.getStatus());
        assertEquals(null, nativeAttempt.getActive_key());
    }

    @Test
    void amountMutationBlocksWhenActiveNativeAttemptIsSuccess() {
        Order order = order();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        WechatNativePaymentAttemptEntity nativeAttempt = activeNativeAttempt();
        when(nativeAttemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(nativeAttempt);
        WechatNativeApiClient.QueryResult query = new WechatNativeApiClient.QueryResult();
        query.tradeState = "SUCCESS";
        when(apiClient.query(7, "1", 11L, 2, "OUT-NAT-1")).thenReturn(query);

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> service.prepareForAmountMutation(order));

        assertTrue(error.getMessage().contains("已被微信支付"));
        verify(apiClient, never()).close(anyInt(), anyString(), any(), any(), anyString());
    }

    @Test
    void amountMutationBlocksWhenActiveNativeAttemptCloseFails() {
        Order order = order();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(attemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        WechatNativePaymentAttemptEntity nativeAttempt = activeNativeAttempt();
        when(nativeAttemptMapper.selectOne(any(QueryWrapper.class))).thenReturn(nativeAttempt);
        WechatNativeApiClient.QueryResult query = new WechatNativeApiClient.QueryResult();
        query.tradeState = "NOTPAY";
        when(apiClient.query(7, "1", 11L, 2, "OUT-NAT-1")).thenReturn(query);
        org.mockito.Mockito.doThrow(new RuntimeException("close failed"))
                .when(apiClient).close(7, "1", 11L, 2, "OUT-NAT-1");

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> service.prepareForAmountMutation(order));

        assertTrue(error.getMessage().contains("旧微信Native支付单未能安全关闭"));
        assertEquals("UNKNOWN", nativeAttempt.getStatus());
        assertEquals("7:ORDER-1", nativeAttempt.getActive_key());
    }

    private static WechatNativePaymentAttemptEntity activeNativeAttempt() {
        WechatNativePaymentAttemptEntity attempt = new WechatNativePaymentAttemptEntity();
        attempt.setId(30L);
        attempt.setShop_id(7);
        attempt.setOrder_id(10);
        attempt.setOrder_no("ORDER-1");
        attempt.setOut_trade_no("OUT-NAT-1");
        attempt.setMerchant_id("1");
        attempt.setMerchant_config_id(11L);
        attempt.setMerchant_config_version(2);
        attempt.setAmount_fen(1250);
        attempt.setStatus("ACTIVE");
        attempt.setTrade_state("NOTPAY");
        attempt.setActive_key("7:ORDER-1");
        attempt.setExpires_at(new Date(System.currentTimeMillis() + 60_000));
        return attempt;
    }

    private static Order order() {
        Order order = new Order();
        order.setId(10);
        order.setShop_id(7);
        order.setOrder_no("ORDER-1");
        order.setTransac_status("unsettled");
        order.setSett_amount(12.5d);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        return order;
    }

    private static WechatJsapiPaymentAttemptEntity activeAttempt() {
        WechatJsapiPaymentAttemptEntity attempt = new WechatJsapiPaymentAttemptEntity();
        attempt.setId(20L);
        attempt.setShop_id(7);
        attempt.setOrder_id(10);
        attempt.setOrder_no("ORDER-1");
        attempt.setOut_trade_no("OUT-1");
        attempt.setMerchant_id("1");
        attempt.setMerchant_config_id(9L);
        attempt.setMerchant_config_version(3);
        attempt.setAmount_fen(1250);
        attempt.setPayer_openid("OPENID-1");
        attempt.setPrepay_id("PREPAY-1");
        attempt.setStatus("ACTIVE");
        attempt.setTrade_state("NOTPAY");
        attempt.setActive_key("7:ORDER-1");
        attempt.setExpires_at(new Date(System.currentTimeMillis() + 60_000));
        return attempt;
    }
}
