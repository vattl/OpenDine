package com.lanf.controller;

import com.lanf.annotation.NoAuth;
import com.lanf.service.PersonalPaymentWebhookService;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 个人收款（支付宝 / 微信）手机监听 App 回调与健康检查接口
 */
@RestController
@RequestMapping("/api/v1/personal-alipay")
@RequiredArgsConstructor
public class PersonalAlipayWebhookController {

    private static final Logger log = LoggerFactory.getLogger(PersonalAlipayWebhookController.class);

    private final PersonalPaymentWebhookService personalPaymentWebhookService;

    /**
     * Webhook 通信签名密钥（与手机端 App 填写的保持一致）
     */
    @Value("${payment.personal-collect.webhook-secret:${personal-alipay.webhook-secret:my_secret_key_888}}")
    private String webhookSecret;

    /**
     * 收款到账异步通知回调接口
     */
    @NoAuth
    @PostMapping(value = "/notify", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> notify(
            @RequestHeader(value = "x-signature", required = false) String xSignatureLower,
            @RequestHeader(value = "X-Signature", required = false) String xSignatureUpper,
            @RequestBody(required = false) Map<String, Object> body) {

        if (body == null) {
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("success", false);
            err.put("message", "empty body");
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(err);
        }

        String clientSignature = StringUtils.hasText(xSignatureLower)
                ? xSignatureLower.trim()
                : (StringUtils.hasText(xSignatureUpper) ? xSignatureUpper.trim() : "");

        String channel = body.get("channel") != null ? body.get("channel").toString().trim() : "";
        Object amountObj = body.get("amount");
        String amountStr = amountObj != null ? amountObj.toString().trim() : "";
        Object timestampObj = body.get("timestamp");
        String timestampStr = timestampObj != null ? timestampObj.toString().trim() : "";
        Object eventIdObj = body.get("event_id") != null ? body.get("event_id") : body.get("eventId");
        String eventId = eventIdObj != null ? eventIdObj.toString().trim() : "";
        Object rawTextObj = body.get("raw_text") != null ? body.get("raw_text") : body.get("rawText");
        String rawText = rawTextObj != null ? rawTextObj.toString() : "";

        // 1. 组装签名 Payload: `${channel}\n${amount}\n${timestamp}\n${event_id}`
        String payload = String.format("%s\n%s\n%s\n%s", channel, amountStr, timestampStr, eventId);
        String expectedSignature = calculateHmacSha256Hex(webhookSecret, payload);

        // 2. 校验签名是否合法
        if (!isSignatureValid(clientSignature, expectedSignature)) {
            log.warn("个人收款回调签名错误，拒绝处理: channel={}, amount={}, timestamp={}, event_id={}, clientSig={}, expectedSig={}",
                    channel, amountStr, timestampStr, eventId, clientSignature, expectedSignature);
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("success", false);
            err.put("message", "bad signature");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(err);
        }

        // 3. 幂等检查（判断 event_id 是否已经处理过）
        if (personalPaymentWebhookService.isEventProcessed(eventId)) {
            log.info("个人收款事件重复推送，返回幂等响应: eventId={}", eventId);
            Map<String, Object> resp = new LinkedHashMap<>();
            resp.put("success", true);
            resp.put("duplicate", true);
            return ResponseEntity.ok(resp);
        }

        // 4. 业务处理
        long amountFen = 0;
        if (amountObj instanceof Number) {
            amountFen = ((Number) amountObj).longValue();
        } else if (StringUtils.hasText(amountStr)) {
            try {
                amountFen = Long.parseLong(amountStr);
            } catch (NumberFormatException ignored) {
            }
        }

        Integer shopId = null;
        if (body.get("shop_id") instanceof Number) {
            shopId = ((Number) body.get("shop_id")).intValue();
        } else if (body.get("shopId") instanceof Number) {
            shopId = ((Number) body.get("shopId")).intValue();
        }

        // merchantId：指定本次到账要匹配的门店（跨门店时由回调方显式传入，为空则由服务端默认门店 1）
        Integer merchantId = null;
        Object merchantObj = body.get("merchant_id") != null ? body.get("merchant_id") : body.get("merchantId");
        if (merchantObj instanceof Number) {
            merchantId = ((Number) merchantObj).intValue();
        } else if (merchantObj != null) {
            try {
                merchantId = Integer.valueOf(merchantObj.toString().trim());
            } catch (NumberFormatException ignored) {
            }
        }

        personalPaymentWebhookService.processPayment(eventId, channel, amountFen, timestampStr, rawText, shopId, merchantId);

        // 5. 必须返回 HTTP 200 及 {"success": true}，App 收到后才会停止重试
        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("success", true);
        return ResponseEntity.ok(resp);
    }

    /**
     * 健康检查连通性测试接口（供 App 首页“测试服务器”按钮调用）
     */
    @NoAuth
    @RequestMapping(value = "/ping", method = {RequestMethod.POST, RequestMethod.GET}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> ping() {
        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("success", true);
        return ResponseEntity.ok(resp);
    }

    /**
     * 计算 HMAC-SHA256 十六进制字符串
     */
    public static String calculateHmacSha256Hex(String secret, String payload) {
        if (secret == null) {
            secret = "";
        }
        if (payload == null) {
            payload = "";
        }
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKeySpec = new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
            mac.init(secretKeySpec);
            byte[] rawHmac = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(rawHmac.length * 2);
            for (byte b : rawHmac) {
                hex.append(Character.forDigit((b >> 4) & 0xF, 16));
                hex.append(Character.forDigit(b & 0xF, 16));
            }
            return hex.toString();
        } catch (Exception e) {
            throw new RuntimeException("HMAC-SHA256 calculation failed", e);
        }
    }

    private static boolean isSignatureValid(String clientSignature, String expectedSignature) {
        if (!StringUtils.hasText(clientSignature) || !StringUtils.hasText(expectedSignature)) {
            return false;
        }
        return MessageDigest.isEqual(
                clientSignature.trim().toLowerCase().getBytes(StandardCharsets.UTF_8),
                expectedSignature.trim().toLowerCase().getBytes(StandardCharsets.UTF_8)
        );
    }
}
