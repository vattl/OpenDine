package com.lanf.payment.channel.wechat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class WechatMicropayApiClientTest {
    private static final String KEY = "0123456789abcdef0123456789abcdef";
    private final WechatMerchantKeyStore keyStore = mock(WechatMerchantKeyStore.class);
    private final RestTemplate restTemplate = new RestTemplate();
    private WechatMicropayApiClient client;
    private MockRestServiceServer server;

    @BeforeEach
    void setUp() {
        client = new WechatMicropayApiClient();
        ReflectionTestUtils.setField(client, "merchantKeyStore", keyStore);
        ReflectionTestUtils.setField(client, "restTemplate", restTemplate);
        server = MockRestServiceServer.bindTo(restTemplate).build();
        WechatMerchantKeyStore.ResolvedMerchant merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.appId = "wx-app"; merchant.mchId = "mch-1"; merchant.apiV2Key = KEY;
        when(keyStore.resolveForPay(7, "1", null)).thenReturn(merchant);
    }

    @Test
    void acceptsOnlySignedMatchingSuccess() {
        server.expect(requestTo("https://api.mch.weixin.qq.com/pay/micropay"))
                .andRespond(withSuccess(response("ORDER-1", "mch-1"), MediaType.APPLICATION_XML));

        WechatMicropayApiClient.Result result = client.pay(
                7, "1", "ORDER-1", 1250, "123456789012345678", "POS-1", "127.0.0.1");

        assertEquals("SUCCESS", result.tradeState);
        assertEquals(1250, result.totalFee);
        server.verify();
    }

    @Test
    void rejectsSignedResponseForAnotherMerchantOrder() {
        server.expect(requestTo("https://api.mch.weixin.qq.com/pay/micropay"))
                .andRespond(withSuccess(response("OTHER", "mch-1"), MediaType.APPLICATION_XML));

        assertThrows(WechatMicropayApiClient.ApiException.class, () -> client.pay(
                7, "1", "ORDER-1", 1250, "123456789012345678", "POS-1", "127.0.0.1"));
    }

    private static String response(String outTradeNo, String mchId) {
        Map<String, String> values = new LinkedHashMap<>();
        values.put("return_code", "SUCCESS"); values.put("result_code", "SUCCESS");
        values.put("appid", "wx-app"); values.put("mch_id", mchId); values.put("out_trade_no", outTradeNo);
        values.put("transaction_id", "WX-TX-1"); values.put("total_fee", "1250");
        values.put("trade_type", "MICROPAY"); values.put("time_end", "20261015120000");
        values.put("sign", WechatPayV2Codec.sign(values, KEY));
        return WechatPayV2Codec.toXml(values);
    }
}
