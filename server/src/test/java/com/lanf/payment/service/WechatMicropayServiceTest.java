package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatMicropayApiClient;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.entity.WechatMicropayAttemptEntity;
import com.lanf.payment.mapper.WechatMicropayAttemptMapper;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class WechatMicropayServiceTest {
    private final IOrderService orderService = mock(IOrderService.class);
    private final WechatMicropayAttemptMapper mapper = mock(WechatMicropayAttemptMapper.class);
    private final WechatMicropayApiClient client = mock(WechatMicropayApiClient.class);
    private final PaymentOnlineGuardService guard = mock(PaymentOnlineGuardService.class);
    private final WechatPaymentSuccessService success = mock(WechatPaymentSuccessService.class);
    private final WechatMerchantKeyStore keyStore = mock(WechatMerchantKeyStore.class);
    private final WechatMerchantRoutingService routingService = mock(WechatMerchantRoutingService.class);
    private WechatMicropayService service;

    @BeforeEach
    void setUp() {
        service = new WechatMicropayService();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "attemptMapper", mapper);
        ReflectionTestUtils.setField(service, "apiClient", client);
        ReflectionTestUtils.setField(service, "onlineGuardService", guard);
        ReflectionTestUtils.setField(service, "successService", success);
        ReflectionTestUtils.setField(service, "merchantKeyStore", keyStore);
        ReflectionTestUtils.setField(service, "merchantRoutingService", routingService);
        WechatMerchantKeyStore.ResolvedMerchant merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.dbConfigId = 11L; merchant.dbConfigVersion = 3; merchant.merchantKey = "default";
        when(keyStore.resolveForPay(any(), any(), any())).thenReturn(merchant);
        when(routingService.route(any(Integer.class), any(Double.class), any(), any())).thenReturn("1");
        when(routingService.route(any(com.lanf.payment.routing.PaymentRoutingContext.class))).thenReturn("1");
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(guard.checkCashierWechatMicropay(any())).thenReturn(null);
    }

    @Test
    void rejectsInvalidAuthCodeBeforePersistenceOrWechatCall() {
        R result = service.pay(7, "ORDER-1", "1234", "POS-1", "127.0.0.1");
        assertEquals(40031, result.get("code"));
        verifyNoInteractions(mapper, client);
    }

    @Test
    void userPayingPersistsNoAuthCodeAndKeepsAttemptQueryable() {
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        when(client.pay(eq(7), eq("1"), eq(11L), eq(3), any(), eq(1250), eq("123456789012345678"), eq("POS-1"), eq("127.0.0.1")))
                .thenReturn(WechatMicropayApiClient.Result.pendingUserPaying());

        R result = service.pay(7, "ORDER-1", "123456789012345678", "POS-1", "127.0.0.1");

        assertEquals(0, result.get("code"));
        assertEquals("USERPAYING", result.get("tradeState"));
        assertNull(result.get("authCode"));
        verify(mapper).insert(any(WechatMicropayAttemptEntity.class));
    }

    @Test
    void querySuccessUsesSharedSettlement() {
        WechatMicropayAttemptEntity attempt = new WechatMicropayAttemptEntity();
        attempt.setId(9L); attempt.setOrder_no("ORDER-1"); attempt.setOut_trade_no("ORDER-1_123");
        attempt.setMerchant_id("1"); attempt.setAmount_fen(1250); attempt.setActive_key("7:ORDER-1");
        attempt.setMerchant_config_id(11L); attempt.setMerchant_config_version(3);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        when(client.query(7, "1", 11L, 3, "ORDER-1_123"))
                .thenReturn(WechatMicropayApiClient.Result.success("WX-1", 1250, "20261015120000"));
        attempt.setShop_id(7);
        when(success.apply(eq("ORDER-1"), eq("ORDER-1_123"), any(), eq("1"), eq(1250), eq(7)))
                .thenReturn(WechatPaymentSuccessService.ApplyResult.applied());

        R result = service.query(7, "ORDER-1");

        assertEquals(0, result.get("code"));
        assertEquals("SUCCESS", result.get("tradeState"));
        assertEquals("SUCCESS", attempt.getStatus());
        assertNull(attempt.getActive_key());
        verify(success).apply(eq("ORDER-1"), eq("ORDER-1_123"), any(), eq("1"), eq(1250), eq(7));
    }

    @Test
    void reverseQueriesFirstThenUsesCertificateEndpoint() {
        WechatMicropayAttemptEntity attempt = new WechatMicropayAttemptEntity();
        attempt.setId(9L); attempt.setShop_id(7); attempt.setOrder_no("ORDER-1");
        attempt.setOut_trade_no("ORDER-1_123"); attempt.setMerchant_id("1"); attempt.setAmount_fen(1250);
        attempt.setMerchant_config_id(11L); attempt.setMerchant_config_version(3);
        attempt.setActive_key("7:ORDER-1"); attempt.setCreated_at(new Date(System.currentTimeMillis() - 20_000));
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order());
        when(mapper.selectOne(any(QueryWrapper.class))).thenReturn(attempt);
        WechatMicropayApiClient.Result notPaid = new WechatMicropayApiClient.Result();
        notPaid.resultCode = "SUCCESS"; notPaid.tradeState = "NOTPAY";
        WechatMicropayApiClient.Result reversed = new WechatMicropayApiClient.Result();
        reversed.resultCode = "SUCCESS"; reversed.tradeState = "REVERSED";
        when(client.query(7, "1", 11L, 3, "ORDER-1_123")).thenReturn(notPaid);
        when(client.reverse(7, "1", 11L, 3, "ORDER-1_123")).thenReturn(reversed);

        R result = service.reverse(7, "ORDER-1");

        assertEquals(0, result.get("code"));
        assertEquals("REVERSED", attempt.getStatus());
        assertNull(attempt.getActive_key());
        verify(client).query(7, "1", 11L, 3, "ORDER-1_123");
        verify(client).reverse(7, "1", 11L, 3, "ORDER-1_123");
    }

    private static Order order() {
        Order order = new Order();
        order.setId(10); order.setOrder_no("ORDER-1"); order.setShop_id(7);
        order.setSett_amount(12.5d); order.setDiscount_amount(0d); order.setService_fee(0d);
        order.setTransac_status("unsettled"); order.setMerchantId("1");
        order.setDineInOrTakeOut("堂食");
        return order;
    }
}
