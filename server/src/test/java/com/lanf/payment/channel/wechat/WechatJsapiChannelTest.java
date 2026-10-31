package com.lanf.payment.channel.wechat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.service.PaymentRefundLedger;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.security.PrivateKey;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatJsapiChannelTest {

    private final WechatMerchantKeyStore merchantKeyStore = mock(WechatMerchantKeyStore.class);
    private final RestTemplate restTemplate = mock(RestTemplate.class);
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

    private WechatJsapiChannel channel() {
        WechatJsapiChannel c = new WechatJsapiChannel();
        ReflectionTestUtils.setField(c, "merchantKeyStore", merchantKeyStore);
        ReflectionTestUtils.setField(c, "paymentRefundLedger", ledger);
        ReflectionTestUtils.setField(c, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(c, "restTemplate", restTemplate);
        return c;
    }

    private static Order order() {
        Order o = new Order();
        o.setOrder_no("ORD-1");
        o.setShop_id(7);
        o.setMerchantId("1");
        o.setMerchant_config_id(9L);
        o.setMerchant_config_version(2);
        o.setTransaction_id("TX-1");
        return o;
    }

    private static WechatMerchantKeyStore.ResolvedMerchant merchant(String refundNotifyUrl) {
        WechatMerchantKeyStore.ResolvedMerchant m = new WechatMerchantKeyStore.ResolvedMerchant();
        m.mchId = "1900000001";
        m.dbConfigId = 9L;
        m.dbConfigVersion = 2;
        m.serialNo = "SERIAL-1";
        m.platformPubKeyId = "PUB-SERIAL-1";
        m.refundNotifyUrl = refundNotifyUrl;
        m.privateKey = rsaPrivateKey();
        return m;
    }

    private static PrivateKey rsaPrivateKey() {
        try {
            return java.security.KeyPairGenerator.getInstance("RSA").generateKeyPair().getPrivate();
        } catch (Exception e) {
            throw new IllegalStateException("无法生成测试 RSA 密钥", e);
        }
    }

    private static Map<String, Object> entry(String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("order_no", "ORD-1");
        row.put("idempotency_key", "KEY-1");
        row.put("out_refund_no", refundNo());
        row.put("requested_fen", 1000);
        row.put("applied_fen", 0);
        row.put("status", status);
        row.put("shop_id", 7);
        row.put("merchant_config_id", 9L);
        row.put("merchant_config_version", 2);
        row.put("expected_transaction_id", "TX-1");
        row.put("expected_mch_id", "1900000001");
        return row;
    }

    private static String refundNo() {
        return com.lanf.payment.support.PaymentOrderNoUtil.buildOutRefundNo("ORD-1", "KEY-1");
    }

    private static Map<String, Object> guard() {
        Map<String, Object> row = new HashMap<>();
        row.put("idempotency_key", "KEY-1");
        return row;
    }

    private void stubReserve() {
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(entry("REQUESTED")),
                        Collections.singletonList(guard()));
    }

    @Test
    void domesticRefundRejectsWhenRefundNotifyUrlMissing() {
        stubReserve();
        when(merchantKeyStore.resolveBound(9L, 2, 7)).thenReturn(merchant(null));

        R result = channel().domesticRefund(order(), 1000, 10000, "测试退款", "KEY-1");

        assertEquals(500, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("refund_notify_url"));
        verify(jdbc).update(
                org.mockito.ArgumentMatchers.contains("status = 'FAILED'"),
                eq(7), eq("KEY-1"));
    }

    @Test
    void domesticRefundProceedsWhenNotifyUrlConfigured() {
        stubReserve();
        when(merchantKeyStore.resolveBound(9L, 2, 7)).thenReturn(merchant("https://cb.example/refund"));
        when(restTemplate.postForObject(anyString(), any(), eq(String.class)))
                .thenReturn("{\"status\":\"PROCESSING\",\"out_refund_no\":\"" + refundNo()
                        + "\",\"refund_id\":\"RID-1\"}");

        R result = channel().domesticRefund(order(), 1000, 10000, "测试退款", "KEY-1");

        assertEquals(0, result.get("code"));
        assertEquals(refundNo(), result.get("out_refund_no"));
        assertEquals("PROCESSING", result.get("refund_status"));
    }

    @Test
    void queryDomesticRefundParsesSuccessResponse() {
        WechatJsapiChannel c = channel();
        when(merchantKeyStore.resolveBound(9L, 2, 7)).thenReturn(merchant("https://cb.example/refund"));
        when(restTemplate.exchange(anyString(), any(), any(), eq(String.class)))
                .thenReturn(new org.springframework.http.ResponseEntity<>(
                        "{\"status\":\"SUCCESS\",\"refund_id\":\"RID-1\",\"amount\":{\"refund\":500,\"total\":10000}}",
                        org.springframework.http.HttpStatus.OK));

        R result = c.queryDomesticRefund(order(), "RF-1");

        assertEquals(0, result.get("code"));
        assertEquals("SUCCESS", result.get("status"));
        assertEquals(500, result.get("amount_refund_fen"));
        assertNotNull(result.get("refund_id"));
    }

    @Test
    void queryDomesticRefundRejectsWhenMerchantCredentialsMissing() {
        WechatMerchantKeyStore.ResolvedMerchant m = merchant("https://cb.example/refund");
        m.privateKey = null;
        when(merchantKeyStore.resolveBound(9L, 2, 7)).thenReturn(m);

        R result = channel().queryDomesticRefund(order(), "RF-1");

        assertEquals(500, result.get("code"));
    }

    @Test
    void createPrepayIncludesSupportFapiao() {
        WechatMerchantKeyStore.ResolvedMerchant m = merchant("https://cb.example/refund");
        m.appId = "wx_test_appid";
        m.notifyUrl = "https://cb.example/pay";
        m.signer = null;
        when(merchantKeyStore.resolveForPay(any(), any(), any())).thenReturn(m);

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        when(restTemplate.postForObject(anyString(), entityCaptor.capture(), eq(String.class)))
                .thenReturn("{\"prepay_id\":\"wx_test_prepay_123\"}");

        com.lanf.service.IOrderService orderServiceMock = mock(com.lanf.service.IOrderService.class);
        when(orderServiceMock.updateById(any(Order.class))).thenReturn(true);
        WechatJsapiChannel c = channel();
        ReflectionTestUtils.setField(c, "orderService", orderServiceMock);

        R result = c.createPrepay(order(), "ORD-1", "openid_123", "0", 100.0, "1", "老肥油边王");
        assertEquals(0, result.get("code"));

        String body = (String) entityCaptor.getValue().getBody();
        assertNotNull(body);
        assertTrue(body.contains("\"support_fapiao\":true"), "统一下单参数必须包含 support_fapiao: true");
    }
}
