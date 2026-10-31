package com.lanf.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.service.WechatRefundSettlementService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * 退款回调 {@code OrderController#handleRefundNotify} 回归：
 * 验签/解密须走 DB 配置解析（{@code WechatMerchantKeyStore#resolveNotifyContext} + 候选 APIv3 密钥遍历），
 * 与支付回调 {@code WechatPaymentNotifyHandler} 同口径；入账统一走严格退款申请绑定入口。
 */
class OrderRefundNotifyTest {

    private static final String API_V3_KEY = "0123456789abcdef0123456789abcdef"; // 32 位
    private static final String ORDER_NO = "ORD20260905040501479";
    private static final String OUT_TRADE_NO = "ORD20260905040501479_1";
    private static final String OUT_REFUND_NO = "RF_ORD20260905040501479_01333ce63167425ed87c";
    private static final String NOTIFY_ID = "notify-2026090501";

    private OrderController orderController;
    private WechatMerchantKeyStore merchantKeyStore;
    private IOrderService orderService;
    private ObjectMapper objectMapper;
    private WechatRefundSettlementService settlementService;

    @BeforeEach
    void setUp() {
        orderController = new OrderController();
        merchantKeyStore = mock(WechatMerchantKeyStore.class);
        orderService = mock(IOrderService.class);
        settlementService = mock(WechatRefundSettlementService.class);
        objectMapper = new ObjectMapper();

        ReflectionTestUtils.setField(orderController, "merchantKeyStore", merchantKeyStore);
        ReflectionTestUtils.setField(orderController, "orderService", orderService);
        ReflectionTestUtils.setField(orderController, "objectMapper", objectMapper);
        ReflectionTestUtils.setField(orderController, "wechatRefundSettlementService", settlementService);
    }

    private WechatMerchantKeyStore.NotifyContext validCtx() {
        WechatMerchantKeyStore.NotifyContext ctx = new WechatMerchantKeyStore.NotifyContext();
        ctx.signatureValid = true;
        ctx.legacyMerchantId = "1";
        ctx.apiV3KeyCandidates = Collections.singletonList(API_V3_KEY);
        return ctx;
    }

    private String encrypt(String plaintext, String associatedData, String nonce, String apiV3Key) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        SecretKeySpec key = new SecretKeySpec(apiV3Key.getBytes(StandardCharsets.UTF_8), "AES");
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, nonce.getBytes(StandardCharsets.UTF_8)));
        if (associatedData != null && !associatedData.isEmpty()) {
            cipher.updateAAD(associatedData.getBytes(StandardCharsets.UTF_8));
        }
        return Base64.getEncoder().encodeToString(cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8)));
    }

    private String buildNotifyBody(String notifyId, String eventType, String plain,
                                   String associatedData, String nonce, String apiV3Key) throws Exception {
        Map<String, Object> resource = new HashMap<>();
        resource.put("algorithm", "AEAD_AES_256_GCM");
        resource.put("ciphertext", encrypt(plain, associatedData, nonce, apiV3Key));
        resource.put("associated_data", associatedData);
        resource.put("nonce", nonce);
        Map<String, Object> root = new HashMap<>();
        root.put("id", notifyId);
        root.put("event_type", eventType);
        root.put("resource_type", "encrypt-resource");
        root.put("resource", resource);
        return objectMapper.writeValueAsString(root);
    }

    private String refundPlain(String outTradeNo, String outRefundNo, String refundStatus, int refundFen) {
        return "{\"mchid\":\"1900000001\",\"out_trade_no\":\"" + outTradeNo
                + "\",\"transaction_id\":\"4200000001202609050000000000\""
                + ",\"out_refund_no\":\"" + outRefundNo
                + "\",\"refund_id\":\"50301308612026090580328768172\""
                + ",\"refund_status\":\"" + refundStatus + "\",\"success_time\":\"2026-09-05T12:00:00+08:00\""
                + ",\"amount\":{\"total\":1000,\"refund\":" + refundFen
                + ",\"payer_total\":1000,\"payer_refund\":" + refundFen + "}}";
    }

    private String callNotify(String body) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setContent(body.getBytes(StandardCharsets.UTF_8));
        MockHttpServletResponse response = new MockHttpServletResponse();
        orderController.handleRefundNotify(request, response);
        return response.getContentAsString();
    }

    private Order order() {
        Order order = new Order();
        order.setId(13899);
        order.setOrder_no(ORDER_NO);
        order.setTransaction_id("4200000001202609050000000000");
        return order;
    }

    @Test
    void refundSuccessNotify_settlesOrderAndReturnsSuccess() throws Exception {
        when(merchantKeyStore.resolveNotifyContext(any(), anyString())).thenReturn(validCtx());

        String body = buildNotifyBody(NOTIFY_ID, "REFUND.SUCCESS",
                refundPlain(OUT_TRADE_NO, OUT_REFUND_NO, "SUCCESS", 100), "refund", "abcdefghijkl", API_V3_KEY);
        String resp = callNotify(body);

        assertTrue(resp.contains("\"code\":\"SUCCESS\""));
        verify(settlementService).settleNotification(
                OUT_REFUND_NO, 100, "4200000001202609050000000000", "1900000001");
    }

    @Test
    void signatureInvalid_returnsFailWithoutSettling() throws Exception {
        WechatMerchantKeyStore.NotifyContext bad = validCtx();
        bad.signatureValid = false;
        when(merchantKeyStore.resolveNotifyContext(any(), anyString())).thenReturn(bad);

        String body = buildNotifyBody(NOTIFY_ID, "REFUND.SUCCESS",
                refundPlain(OUT_TRADE_NO, OUT_REFUND_NO, "SUCCESS", 100), "refund", "abcdefghijkl", API_V3_KEY);
        String resp = callNotify(body);

        assertTrue(resp.contains("\"message\":\"签名验证失败\""));
        verifyNoInteractions(settlementService);
    }

    @Test
    void resolveContextNull_returnsFailWithoutSettling() throws Exception {
        when(merchantKeyStore.resolveNotifyContext(any(), anyString())).thenReturn(null);

        String body = buildNotifyBody(NOTIFY_ID, "REFUND.SUCCESS",
                refundPlain(OUT_TRADE_NO, OUT_REFUND_NO, "SUCCESS", 100), "refund", "abcdefghijkl", API_V3_KEY);
        String resp = callNotify(body);

        assertTrue(resp.contains("\"message\":\"签名验证失败\""));
        verifyNoInteractions(settlementService);
    }

    @Test
    void wrongApiV3KeyCandidates_decryptFailsReturnsFailWithoutSettling() throws Exception {
        WechatMerchantKeyStore.NotifyContext ctx = validCtx();
        ctx.apiV3KeyCandidates = Collections.singletonList("ffffffffffffffffffffffffffffffff"); // 错误密钥
        when(merchantKeyStore.resolveNotifyContext(any(), anyString())).thenReturn(ctx);

        // 密文用正确密钥加密，候选密钥全错 → 解密失败
        String body = buildNotifyBody(NOTIFY_ID, "REFUND.SUCCESS",
                refundPlain(OUT_TRADE_NO, OUT_REFUND_NO, "SUCCESS", 100), "refund", "abcdefghijkl", API_V3_KEY);
        String resp = callNotify(body);

        assertTrue(resp.contains("\"message\":\"解密失败\""));
        verifyNoInteractions(settlementService);
    }

    @Test
    void duplicateNotifyId_settlesOnlyOnce() throws Exception {
        when(merchantKeyStore.resolveNotifyContext(any(), anyString())).thenReturn(validCtx());

        String body = buildNotifyBody(NOTIFY_ID, "REFUND.SUCCESS",
                refundPlain(OUT_TRADE_NO, OUT_REFUND_NO, "SUCCESS", 100), "refund", "abcdefghijkl", API_V3_KEY);
        callNotify(body);
        callNotify(body); // 微信重试同一条通知

        verify(settlementService, times(1)).settleNotification(
                OUT_REFUND_NO, 100, "4200000001202609050000000000", "1900000001");
    }

    @Test
    void refundStatusProcessing_returnsOkWithoutSettling() throws Exception {
        when(merchantKeyStore.resolveNotifyContext(any(), anyString())).thenReturn(validCtx());

        String body = buildNotifyBody(NOTIFY_ID, "REFUND.SUCCESS",
                refundPlain(OUT_TRADE_NO, OUT_REFUND_NO, "PROCESSING", 100), "refund", "abcdefghijkl", API_V3_KEY);
        String resp = callNotify(body);

        assertTrue(resp.contains("\"code\":\"SUCCESS\""));
        verifyNoInteractions(settlementService);
    }
}
