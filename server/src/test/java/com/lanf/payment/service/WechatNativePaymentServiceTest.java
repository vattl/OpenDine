package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatNativeApiClient;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import com.lanf.payment.mapper.WechatNativePaymentAttemptMapper;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.HttpClientErrorException;

import java.nio.charset.StandardCharsets;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatNativePaymentServiceTest {

    private final IOrderService orderService = mock(IOrderService.class);
    private final WechatNativePaymentAttemptMapper mapper = mock(WechatNativePaymentAttemptMapper.class);
    private final WechatNativeApiClient client = mock(WechatNativeApiClient.class);
    private final PaymentOnlineGuardService guard = mock(PaymentOnlineGuardService.class);
    private final WechatPaymentSuccessService successService = mock(WechatPaymentSuccessService.class);
    private final WechatMerchantKeyStore keyStore = mock(WechatMerchantKeyStore.class);
    private final WechatMerchantRoutingService routingService = mock(WechatMerchantRoutingService.class);
    private WechatNativePaymentService service;

    @BeforeEach
    void setUp() {
        service = new WechatNativePaymentService();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "attemptMapper", mapper);
        ReflectionTestUtils.setField(service, "apiClient", client);
        ReflectionTestUtils.setField(service, "onlineGuardService", guard);
        ReflectionTestUtils.setField(service, "successService", successService);
        ReflectionTestUtils.setField(service, "merchantKeyStore", keyStore);
        ReflectionTestUtils.setField(service, "merchantRoutingService", routingService);
        WechatMerchantKeyStore.ResolvedMerchant merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.dbConfigId = 11L; merchant.dbConfigVersion = 3; merchant.merchantKey = "default";
        when(keyStore.resolveForPay(any(), any(), any())).thenReturn(merchant);
        when(routingService.route(any(Integer.class), any(Double.class), any(), any())).thenReturn("1");
        when(routingService.route(any(com.lanf.payment.routing.PaymentRoutingContext.class))).thenReturn("1");
        when(orderService.updateById(any(Order.class))).thenReturn(true);
    }

    @Test
    void createUsesServerAmountAndReusesLiveCodeUrl() {
        Order order = order();
        WechatNativePaymentAttemptEntity active = new WechatNativePaymentAttemptEntity();
        active.setId(5L);
        active.setOrder_no("ORDER-1");
        active.setOut_trade_no("ORDER-1_123");
        active.setAmount_fen(1250);
        active.setCode_url("weixin://wxpay/bizpayurl?pr=old");
        active.setStatus("ACTIVE");
        active.setExpires_at(new Date(System.currentTimeMillis() + 60_000));
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(active);

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, result.get("code"));
        assertEquals(1250, result.get("amountFen"));
        assertEquals(true, result.get("reused"));
        verify(client, never()).create(any(), any(), any(), any(), any(), any());
    }

    @Test
    void querySuccessInvokesSharedSettlementCompensation() {
        Order order = order();
        WechatNativePaymentAttemptEntity active = new WechatNativePaymentAttemptEntity();
        active.setId(5L);
        active.setOrder_no("ORDER-1");
        active.setOut_trade_no("ORDER-1_123");
        active.setAmount_fen(1250);
        active.setMerchant_id("1");
        active.setMerchant_config_id(11L);
        active.setMerchant_config_version(3);
        active.setShop_id(7);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(active);
        when(client.query(eq(7), eq("1"), eq(11L), eq(3), eq("ORDER-1_123")))
                .thenReturn(WechatNativeApiClient.QueryResult.success("WX-TX-1", 1250, "2026-10-15T12:00:00+08:00"));
        when(successService.apply(eq("ORDER-1"), eq("ORDER-1_123"), any(), eq("1"), eq(1250), eq(7)))
                .thenReturn(WechatPaymentSuccessService.ApplyResult.applied());

        R result = service.query(7, "ORDER-1");

        assertEquals(0, result.get("code"));
        assertEquals("SUCCESS", result.get("tradeState"));
        verify(successService).apply(eq("ORDER-1"), eq("ORDER-1_123"), any(), eq("1"), eq(1250), eq(7));
        verify(mapper).updateById(active);
        assertEquals("SUCCESS", active.getStatus());
        assertTrue(active.getActive_key() == null);
    }

    @Test
    void createDoesNotReplaceAnUnknownAttemptThatCouldStillBePayable() {
        WechatNativePaymentAttemptEntity unknown = new WechatNativePaymentAttemptEntity();
        unknown.setOrder_no("ORDER-1");
        unknown.setOut_trade_no("ORDER-1_123");
        unknown.setAmount_fen(1250);
        unknown.setStatus("UNKNOWN");
        unknown.setActive_key("7:ORDER-1");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(unknown);

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(40931, result.get("code"));
        verify(client, never()).create(any(), any(), any(), any(), any(), any());
    }

    @Test
    void concurrentCreateWaitsForWinnerAndReusesItsCodeUrl() {
        WechatNativePaymentAttemptEntity creating = new WechatNativePaymentAttemptEntity();
        creating.setOrder_no("ORDER-1");
        creating.setOut_trade_no("ORDER-1_123");
        creating.setAmount_fen(1250);
        creating.setStatus("CREATING");
        creating.setActive_key("7:ORDER-1");

        WechatNativePaymentAttemptEntity active = new WechatNativePaymentAttemptEntity();
        active.setId(5L);
        active.setOrder_no("ORDER-1");
        active.setOut_trade_no("ORDER-1_123");
        active.setAmount_fen(1250);
        active.setCode_url("weixin://wxpay/bizpayurl?pr=winner");
        active.setStatus("ACTIVE");
        active.setActive_key("7:ORDER-1");
        active.setExpires_at(new Date(System.currentTimeMillis() + 60_000));

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(null, creating, active);
        when(mapper.insert(any(WechatNativePaymentAttemptEntity.class)))
                .thenThrow(new DuplicateKeyException("duplicate active_key"));

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, result.get("code"));
        assertEquals("weixin://wxpay/bizpayurl?pr=winner", result.get("codeUrl"));
        assertEquals(true, result.get("reused"));
        verify(client, never()).create(any(), any(), any(), any(), any(), any());
    }

    @Test
    void concurrentCreateKeepsSafetyErrorWhenWinnerDoesNotFinishInTime() {
        WechatNativePaymentAttemptEntity creating = new WechatNativePaymentAttemptEntity();
        creating.setOrder_no("ORDER-1");
        creating.setOut_trade_no("ORDER-1_123");
        creating.setAmount_fen(1250);
        creating.setStatus("CREATING");
        creating.setActive_key("7:ORDER-1");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(creating);

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(40931, result.get("code"));
        verify(mapper, never()).insert(any(WechatNativePaymentAttemptEntity.class));
        verify(client, never()).create(any(), any(), any(), any(), any(), any());
    }

    @Test
    void createReleasesActiveAttemptWhenWechatExplicitlyRejectsRequest() {
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        HttpHeaders headers = new HttpHeaders();
        headers.set("Request-ID", "wx-request-123");
        HttpClientErrorException rejected = HttpClientErrorException.create(
                HttpStatus.BAD_REQUEST,
                "Bad Request",
                headers,
                "{\"code\":\"PARAM_ERROR\",\"message\":\"appid与mchid不匹配\"}"
                        .getBytes(StandardCharsets.UTF_8),
                StandardCharsets.UTF_8);
        when(client.create(any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(new WechatNativeApiClient.ApiException("微信Native下单失败", rejected,
                        WechatNativeApiClient.FailureType.REJECTED, 400, "PARAM_ERROR",
                        "appid与mchid不匹配", "wx-request-123"));

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(40231, result.get("code"));
        assertEquals("PARAM_ERROR", result.get("wechatCode"));
        assertEquals("wx-request-123", result.get("requestId"));
        org.mockito.ArgumentCaptor<WechatNativePaymentAttemptEntity> inserted =
                org.mockito.ArgumentCaptor.forClass(WechatNativePaymentAttemptEntity.class);
        verify(mapper).insert(inserted.capture());
        WechatNativePaymentAttemptEntity attempt = inserted.getValue();
        assertEquals("CLOSED", attempt.getStatus());
        assertEquals("PAYERROR", attempt.getTrade_state());
        assertEquals(null, attempt.getActive_key());
        verify(mapper).updateById(attempt);
    }

    @Test
    void createKeepsActiveAttemptUnknownWhenWechatFailureIsUncertain() {
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        when(client.create(any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(new WechatNativeApiClient.ApiException("微信Native下单失败",
                        new IllegalStateException("微信响应签名无效"),
                        WechatNativeApiClient.FailureType.UNCERTAIN, 500, "SYSTEM_ERROR", null,
                        "wx-request-500"));

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(50331, result.get("code"));
        org.mockito.ArgumentCaptor<WechatNativePaymentAttemptEntity> inserted =
                org.mockito.ArgumentCaptor.forClass(WechatNativePaymentAttemptEntity.class);
        verify(mapper).insert(inserted.capture());
        WechatNativePaymentAttemptEntity attempt = inserted.getValue();
        assertEquals("UNKNOWN", attempt.getStatus());
        assertEquals("7:ORDER-1", attempt.getActive_key());
        verify(mapper).updateById(attempt);
    }

    @Test
    void createAllowsNewAttemptWhenPreviousAttemptWasClosed() {
        Order order = order();
        WechatNativePaymentAttemptEntity closed = new WechatNativePaymentAttemptEntity();
        closed.setId(5L);
        closed.setOrder_no("ORDER-1");
        closed.setOut_trade_no("ORDER-1_old");
        closed.setAmount_fen(1250);
        closed.setStatus("CLOSED");
        closed.setActive_key("7:ORDER-1");
        closed.setMerchant_id("1");
        closed.setMerchant_config_id(11L);
        closed.setMerchant_config_version(3);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(closed);
        when(client.create(eq(7), eq("1"), eq(11L), eq(3), any(), eq(1250), any(), any()))
                .thenReturn(new WechatNativeApiClient.CreateResult("weixin://wxpay/bizpayurl?pr=new"));

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, result.get("code"));
        assertEquals("weixin://wxpay/bizpayurl?pr=new", result.get("codeUrl"));
        assertEquals(false, result.get("reused"));
        // Does not redundantly call WeChat close since already CLOSED
        verify(client, never()).close(any(), any(), any(), any(), any());
        verify(client).create(eq(7), eq("1"), eq(11L), eq(3), any(), eq(1250), any(), any());
    }

    @Test
    void createClosesActiveAttemptAndAllowsNewAttemptWhenExpired() {
        Order order = order();
        WechatNativePaymentAttemptEntity expired = new WechatNativePaymentAttemptEntity();
        expired.setId(5L);
        expired.setOrder_no("ORDER-1");
        expired.setOut_trade_no("ORDER-1_old");
        expired.setAmount_fen(1250);
        expired.setStatus("ACTIVE");
        expired.setCode_url("weixin://wxpay/bizpayurl?pr=old");
        expired.setActive_key("7:ORDER-1");
        expired.setMerchant_id("1");
        expired.setMerchant_config_id(11L);
        expired.setMerchant_config_version(3);
        expired.setExpires_at(new Date(System.currentTimeMillis() - 60_000)); // expired

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(expired);
        when(client.create(eq(7), eq("1"), eq(11L), eq(3), any(), eq(1250), any(), any()))
                .thenReturn(new WechatNativeApiClient.CreateResult("weixin://wxpay/bizpayurl?pr=new"));

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, result.get("code"));
        assertEquals("weixin://wxpay/bizpayurl?pr=new", result.get("codeUrl"));
        assertEquals(false, result.get("reused"));
        // Expired active attempt must be closed on WeChat before creating new
        verify(client).close(eq(7), eq("1"), eq(11L), eq(3), eq("ORDER-1_old"));
        verify(client).create(eq(7), eq("1"), eq(11L), eq(3), any(), eq(1250), any(), any());
    }

    @Test
    void closeReleasesActiveKeyAndAllowsCreatingANewNativeAttempt() {
        Order order = order();
        WechatNativePaymentAttemptEntity active = new WechatNativePaymentAttemptEntity();
        active.setId(5L);
        active.setShop_id(7);
        active.setOrder_no("ORDER-1");
        active.setOut_trade_no("ORDER-1_123");
        active.setMerchant_id("1");
        active.setMerchant_config_id(11L);
        active.setMerchant_config_version(3);
        active.setAmount_fen(1250);
        active.setStatus("ACTIVE");
        active.setActive_key("7:ORDER-1");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(active, null);
        when(client.create(any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(new WechatNativeApiClient.CreateResult("weixin://wxpay/bizpayurl?pr=new"));

        R closeResult = service.close(7, "ORDER-1");
        R createResult = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, closeResult.get("code"));
        assertEquals(null, active.getActive_key());
        assertEquals("CLOSED", active.getStatus());
        assertEquals(0, createResult.get("code"));
        assertEquals("weixin://wxpay/bizpayurl?pr=new", createResult.get("codeUrl"));
        org.mockito.ArgumentCaptor<WechatNativePaymentAttemptEntity> inserted =
                org.mockito.ArgumentCaptor.forClass(WechatNativePaymentAttemptEntity.class);
        verify(mapper).insert(inserted.capture());
        assertEquals("7:ORDER-1", inserted.getValue().getActive_key());
        verify(client).close(eq(7), eq("1"), eq(11L), eq(3), eq("ORDER-1_123"));
    }

    @Test
    void createRepairsLegacyClosedAttemptWhoseActiveKeyWasNotCleared() {
        WechatNativePaymentAttemptEntity staleClosed = new WechatNativePaymentAttemptEntity();
        staleClosed.setId(5L);
        staleClosed.setShop_id(7);
        staleClosed.setOrder_no("ORDER-1");
        staleClosed.setOut_trade_no("ORDER-1_123");
        staleClosed.setMerchant_id("1");
        staleClosed.setMerchant_config_id(11L);
        staleClosed.setMerchant_config_version(3);
        staleClosed.setAmount_fen(1250);
        staleClosed.setStatus("CLOSED");
        staleClosed.setTrade_state("CLOSED");
        staleClosed.setActive_key("7:ORDER-1");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(staleClosed);
        org.mockito.Mockito.doThrow(new IllegalStateException("ORDER_CLOSED"))
                .when(client).close(any(), any(), any(), any(), any());
        when(client.create(any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(new WechatNativeApiClient.CreateResult("weixin://wxpay/bizpayurl?pr=recovered"));

        R result = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, result.get("code"));
        assertEquals("weixin://wxpay/bizpayurl?pr=recovered", result.get("codeUrl"));
        assertEquals(null, staleClosed.getActive_key());
        verify(client, never()).close(any(), any(), any(), any(), any());
        verify(mapper).updateById(staleClosed);
        verify(mapper).insert(any(WechatNativePaymentAttemptEntity.class));
    }

    @Test
    void closeTreatsNonexistentOrderOnWechatAsSuccessfulClose() {
        Order order = order();
        WechatNativePaymentAttemptEntity active = new WechatNativePaymentAttemptEntity();
        active.setId(5L);
        active.setShop_id(7);
        active.setOrder_no("ORDER-1");
        active.setOut_trade_no("ORDER-1_123");
        active.setMerchant_id("1");
        active.setMerchant_config_id(11L);
        active.setMerchant_config_version(3);
        active.setStatus("UNKNOWN");
        active.setActive_key("7:ORDER-1");

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(active);
        org.mockito.Mockito.doThrow(new WechatNativeApiClient.ApiException("关单失败",
                new org.springframework.web.client.HttpClientErrorException(
                        org.springframework.http.HttpStatus.NOT_FOUND, "Not Found",
                        "{\"code\":\"ORDER_NOT_EXIST\",\"message\":\"订单不存在\"}".getBytes(java.nio.charset.StandardCharsets.UTF_8),
                        java.nio.charset.StandardCharsets.UTF_8),
                WechatNativeApiClient.FailureType.REJECTED, 404, "ORDER_NOT_EXIST", "订单不存在", "req-1"))
                .when(client).close(any(), any(), any(), any(), any());

        R closeResult = service.close(7, "ORDER-1");

        assertEquals(0, closeResult.get("code"));
        assertEquals(true, closeResult.get("closed"));
        assertEquals(true, closeResult.get("nonexistentOnWechat"));
        assertEquals("CLOSED", active.getStatus());
        assertEquals(null, active.getActive_key());
        verify(mapper).updateById(active);
    }

    @Test
    void createReplacesStaleActiveAttemptWhenWechatReportsNonexistent() {
        Order order = order();
        WechatNativePaymentAttemptEntity active = new WechatNativePaymentAttemptEntity();
        active.setId(5L);
        active.setShop_id(7);
        active.setOrder_no("ORDER-1");
        active.setOut_trade_no("ORDER-1_123");
        active.setMerchant_id("1");
        active.setMerchant_config_id(11L);
        active.setMerchant_config_version(3);
        active.setStatus("ACTIVE");
        active.setCode_url("weixin://wxpay/bizpayurl?pr=old");
        active.setExpires_at(new Date(System.currentTimeMillis() - 60_000));
        active.setActive_key("7:ORDER-1");

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(active, (WechatNativePaymentAttemptEntity) null);
        org.mockito.Mockito.doThrow(new WechatNativeApiClient.ApiException("关单失败",
                new org.springframework.web.client.HttpClientErrorException(
                        org.springframework.http.HttpStatus.NOT_FOUND, "Not Found",
                        "{\"code\":\"ORDER_NOT_EXIST\",\"message\":\"订单不存在\"}".getBytes(java.nio.charset.StandardCharsets.UTF_8),
                        java.nio.charset.StandardCharsets.UTF_8),
                WechatNativeApiClient.FailureType.REJECTED, 404, "ORDER_NOT_EXIST", "订单不存在", "req-1"))
                .when(client).close(any(), any(), any(), any(), any());
        when(client.create(any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(new WechatNativeApiClient.CreateResult("weixin://wxpay/bizpayurl?pr=recovered"));

        R createResult = service.create(7, "ORDER-1", "POS-1");

        assertEquals(0, createResult.get("code"));
        assertEquals("weixin://wxpay/bizpayurl?pr=recovered", createResult.get("codeUrl"));
        assertEquals("CLOSED", active.getStatus());
        assertEquals(null, active.getActive_key());
        verify(mapper).updateById(active);
    }

    @Test
    void queryCleansUnknownAttemptWhenWechatReportsNonexistent() {
        Order order = order();
        WechatNativePaymentAttemptEntity attempt = new WechatNativePaymentAttemptEntity();
        attempt.setId(5L);
        attempt.setShop_id(7);
        attempt.setOrder_no("ORDER-1");
        attempt.setOut_trade_no("ORDER-1_123");
        attempt.setMerchant_id("1");
        attempt.setMerchant_config_id(11L);
        attempt.setMerchant_config_version(3);
        attempt.setStatus("UNKNOWN");
        attempt.setActive_key("7:ORDER-1");

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(client.query(any(), any(), any(), any(), any()))
                .thenThrow(new WechatNativeApiClient.ApiException("查单失败",
                        new org.springframework.web.client.HttpClientErrorException(
                                org.springframework.http.HttpStatus.NOT_FOUND, "Not Found",
                                "{\"code\":\"ORDER_NOT_EXIST\",\"message\":\"订单不存在\"}".getBytes(java.nio.charset.StandardCharsets.UTF_8),
                                java.nio.charset.StandardCharsets.UTF_8),
                        WechatNativeApiClient.FailureType.REJECTED, 404, "ORDER_NOT_EXIST", "订单不存在", "req-1"));

        R queryResult = service.query(7, "ORDER-1");

        assertEquals(0, queryResult.get("code"));
        assertEquals("NOTPAY", queryResult.get("tradeState"));
        assertEquals("CLOSED", attempt.getStatus());
        assertEquals(null, attempt.getActive_key());
        verify(mapper).updateById(attempt);
    }

    private static Order order() {
        Order order = new Order();
        order.setId(10);
        order.setOrder_no("ORDER-1");
        order.setShop_id(7);
        order.setSett_amount(12.5d);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        order.setTransac_status("unsettled");
        order.setMerchantId("1");
        order.setDineInOrTakeOut("堂食");
        return order;
    }
}
