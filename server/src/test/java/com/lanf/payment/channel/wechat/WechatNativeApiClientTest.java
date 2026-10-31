package com.lanf.payment.channel.wechat;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.Signature;
import java.util.Base64;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatNativeApiClientTest {

    private final WechatMerchantKeyStore keyStore = mock(WechatMerchantKeyStore.class);
    private final RestTemplate restTemplate = mock(RestTemplate.class);
    private WechatNativeApiClient client;
    private KeyPair merchantKeys;
    private KeyPair platformKeys;
    private WechatMerchantKeyStore.ResolvedMerchant merchant;

    @BeforeEach
    void setUp() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        merchantKeys = generator.generateKeyPair();
        platformKeys = generator.generateKeyPair();

        merchant = new WechatMerchantKeyStore.ResolvedMerchant();
        merchant.appId = "wx-app-1";
        merchant.mchId = "mch-1";
        merchant.notifyUrl = "https://merchant.example/pay/notify";
        merchant.serialNo = "MERCHANT-SERIAL-1";
        merchant.privateKey = merchantKeys.getPrivate();
        merchant.platformPubKeyId = "PUB_KEY_ID_1";
        merchant.wechatPublicKey = platformKeys.getPublic();
        when(keyStore.resolveForPay(7, "1", null)).thenReturn(merchant);

        client = new WechatNativeApiClient();
        ReflectionTestUtils.setField(client, "merchantKeyStore", keyStore);
        ReflectionTestUtils.setField(client, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(client, "restTemplate", restTemplate);
    }

    @Test
    void createAcceptsVerifiedResponseAndUsesExistingMerchantCertificateIdentity() throws Exception {
        String body = "{\"code_url\":\"weixin://wxpay/bizpayurl?pr=signed\"}";
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(String.class))).thenReturn(body);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class)))
                .thenReturn(signedResponse(body, platformKeys.getPrivate(), "PUB_KEY_ID_1", 0));

        WechatNativeApiClient.CreateResult result = client.create(
                7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1", new Date(System.currentTimeMillis() + 60_000));

        assertEquals("weixin://wxpay/bizpayurl?pr=signed", result.codeUrl);
        ArgumentCaptor<HttpEntity> request = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(anyString(), request.capture(), eq(String.class));
        String authorization = request.getValue().getHeaders().getFirst("Authorization");
        assertTrue(authorization.contains("mchid=\"mch-1\""));
        assertTrue(authorization.contains("serial_no=\"MERCHANT-SERIAL-1\""));
    }

    @Test
    void createRejectsInvalidWechatResponseSignature() throws Exception {
        String body = "{\"code_url\":\"weixin://wxpay/bizpayurl?pr=forged\"}";
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(String.class))).thenReturn(body);
        ResponseEntity<String> signed = signedResponse(body, merchantKeys.getPrivate(), "PUB_KEY_ID_1", 0);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class))).thenReturn(signed);

        assertThrows(WechatNativeApiClient.ApiException.class, () -> client.create(
                7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1", new Date(System.currentTimeMillis() + 60_000)));
    }

    @Test
    void createRejectsExpiredWechatResponse() throws Exception {
        String body = "{\"code_url\":\"weixin://wxpay/bizpayurl?pr=replayed\"}";
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(String.class))).thenReturn(body);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class)))
                .thenReturn(signedResponse(body, platformKeys.getPrivate(), "PUB_KEY_ID_1", -601));

        assertThrows(WechatNativeApiClient.ApiException.class, () -> client.create(
                7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1", new Date(System.currentTimeMillis() + 60_000)));
    }

    @Test
    void createRejectsResponseWithMissingSignatureHeaders() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Wechatpay-Serial", "PUB_KEY_ID_1");
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"code_url\":\"untrusted\"}", headers, HttpStatus.OK));

        assertThrows(WechatNativeApiClient.ApiException.class, () -> client.create(
                7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1", new Date(System.currentTimeMillis() + 60_000)));
    }

    @Test
    void queryAcceptsVerifiedWechatResponse() throws Exception {
        String body = "{\"out_trade_no\":\"ORDER-1_123\",\"trade_state\":\"NOTPAY\"}";
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(String.class)))
                .thenReturn(signedResponse(body, platformKeys.getPrivate(), "PUB_KEY_ID_1", 0));

        WechatNativeApiClient.QueryResult result = client.query(7, "1", "ORDER-1_123");

        assertEquals("NOTPAY", result.tradeState);
    }

    @Test
    void createDoesNotCallWechatWhenPlatformPublicKeyCannotBeLoaded() {
        merchant.wechatPublicKey = null;

        WechatNativeApiClient.ApiException error = assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.create(7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1",
                        new Date(System.currentTimeMillis() + 60_000)));

        assertTrue(error.getCause() instanceof IllegalStateException);
        verify(restTemplate, never()).postForObject(anyString(), any(HttpEntity.class), eq(String.class));
        verify(restTemplate, never()).postForEntity(anyString(), any(HttpEntity.class), eq(String.class));
    }

    @Test
    void closeRejectsResponseWithWrongPlatformPublicKeyId() throws Exception {
        String body = "";
        ResponseEntity<String> response = signedResponse(body, platformKeys.getPrivate(), "WRONG_KEY_ID", 0);
        when(restTemplate.exchange(anyString(), eq(HttpMethod.POST), any(HttpEntity.class), eq(String.class)))
                .thenReturn(response);

        assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.close(7, "1", "ORDER-1_123"));
    }

    @Test
    void closeUsesBoundMerchantCredentialsAndSerial() throws Exception {
        when(keyStore.resolveBound(11L, 3, 7)).thenReturn(merchant);
        String body = "";
        ResponseEntity<String> response = signedResponse(body, platformKeys.getPrivate(), "PUB_KEY_ID_1", 0);
        when(restTemplate.exchange(anyString(), eq(HttpMethod.POST), any(HttpEntity.class), eq(String.class)))
                .thenReturn(response);

        client.close(7, "1", 11L, 3, "ORDER-1_123");

        ArgumentCaptor<HttpEntity> request = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).exchange(eq("https://api.mch.weixin.qq.com/v3/pay/transactions/out-trade-no/ORDER-1_123/close"),
                eq(HttpMethod.POST), request.capture(), eq(String.class));
        String authorization = request.getValue().getHeaders().getFirst("Authorization");
        assertTrue(authorization.contains("mchid=\"mch-1\""));
        assertTrue(authorization.contains("serial_no=\"MERCHANT-SERIAL-1\""));
    }

    @Test
    void closeRejectsCrossShopBoundConfig() {
        when(keyStore.resolveBound(11L, 3, 7)).thenReturn(null);

        WechatNativeApiClient.ApiException error = assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.close(7, "1", 11L, 3, "ORDER-1_123"));
        assertTrue(error.getCause() instanceof IllegalStateException);
        verify(restTemplate, never()).exchange(anyString(), any(HttpMethod.class), any(HttpEntity.class), eq(String.class));
    }

    @Test
    void createRejectsCrossShopBoundConfig() {
        when(keyStore.resolveBound(11L, 3, 7)).thenReturn(null);

        WechatNativeApiClient.ApiException error = assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.create(7, "1", 11L, 3, "ORDER-1_123", 1250, "desc",
                        new Date(System.currentTimeMillis() + 60_000)));
        assertTrue(error.getCause() instanceof IllegalStateException);
        verify(restTemplate, never()).postForEntity(anyString(), any(HttpEntity.class), eq(String.class));
    }

    @Test
    void createClassifiesWechatFourHundredAsDefinitiveRejection() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Request-ID", "wx-request-123");
        HttpClientErrorException response = HttpClientErrorException.create(
                HttpStatus.BAD_REQUEST, "Bad Request", headers,
                "{\"code\":\"PARAM_ERROR\",\"message\":\"appid与mchid不匹配\"}"
                        .getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class)))
                .thenThrow(response);

        WechatNativeApiClient.ApiException error = assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.create(7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1",
                        new Date(System.currentTimeMillis() + 60_000)));

        assertTrue(error.isDefinitiveRejection());
        assertEquals(400, error.httpStatus);
        assertEquals("PARAM_ERROR", error.wechatCode);
        assertEquals("appid与mchid不匹配", error.wechatMessage);
        assertEquals("wx-request-123", error.requestId);
    }

    @Test
    void createKeepsWechatFiveHundredAsUncertain() {
        HttpServerErrorException response = HttpServerErrorException.create(
                HttpStatus.INTERNAL_SERVER_ERROR, "Internal Server Error", HttpHeaders.EMPTY,
                "{\"code\":\"SYSTEM_ERROR\",\"message\":\"系统繁忙\"}"
                        .getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class)))
                .thenThrow(response);

        WechatNativeApiClient.ApiException error = assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.create(7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1",
                        new Date(System.currentTimeMillis() + 60_000)));

        assertTrue(!error.isDefinitiveRejection());
        assertEquals(500, error.httpStatus);
        assertEquals("SYSTEM_ERROR", error.wechatCode);
    }

    @Test
    void createSanitizesWechatErrorTextBeforeItCanReachLogsOrApi() {
        HttpClientErrorException response = HttpClientErrorException.create(
                HttpStatus.BAD_REQUEST, "Bad Request", HttpHeaders.EMPTY,
                "{\"code\":\"PARAM_ERROR\\nFORGED\",\"message\":\"第一行\\n第二行\\t请检查\"}"
                        .getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(String.class)))
                .thenThrow(response);

        WechatNativeApiClient.ApiException error = assertThrows(WechatNativeApiClient.ApiException.class,
                () -> client.create(7, "1", "ORDER-1_123", 1250, "门店订单 ORDER-1",
                        new Date(System.currentTimeMillis() + 60_000)));

        assertEquals("PARAM_ERROR FORGED", error.wechatCode);
        assertEquals("第一行 第二行 请检查", error.wechatMessage);
    }

    private static ResponseEntity<String> signedResponse(String body, PrivateKey key, String keyId,
                                                          long timestampOffsetSeconds) throws Exception {
        String timestamp = String.valueOf(System.currentTimeMillis() / 1000 + timestampOffsetSeconds);
        String nonce = "response-nonce";
        Signature signer = Signature.getInstance("SHA256withRSA");
        signer.initSign(key);
        signer.update((timestamp + "\n" + nonce + "\n" + body + "\n").getBytes(StandardCharsets.UTF_8));
        HttpHeaders headers = new HttpHeaders();
        headers.set("Wechatpay-Serial", keyId);
        headers.set("Wechatpay-Timestamp", timestamp);
        headers.set("Wechatpay-Nonce", nonce);
        headers.set("Wechatpay-Signature", Base64.getEncoder().encodeToString(signer.sign()));
        return new ResponseEntity<>(body, headers, HttpStatus.OK);
    }
}
