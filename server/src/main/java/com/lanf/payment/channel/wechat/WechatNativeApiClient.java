package com.lanf.payment.channel.wechat;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.RestTemplate;

import java.text.SimpleDateFormat;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

/** 微信支付 API v3 Native/JSAPI 下单及通用查单、关单客户端。 */
@Component
public class WechatNativeApiClient {
    private static final String API = "https://api.mch.weixin.qq.com";
    private static final long MAX_RESPONSE_AGE_SECONDS = 5 * 60L;

    @Autowired private WechatMerchantKeyStore merchantKeyStore;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private RestTemplate restTemplate;

    public CreateResult create(Integer shopId, String merchantId, String outTradeNo,
                               Integer amountFen, String description, Date expiresAt) {
        return create(shopId, merchantId, null, null, outTradeNo, amountFen, description, expiresAt);
    }

    public CreateResult create(Integer shopId, String merchantId, Long configId, Integer configVersion,
                               String outTradeNo, Integer amountFen, String description, Date expiresAt) {
        try {
            WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion);
            Map<String, Object> body = new HashMap<>();
            body.put("appid", merchant.appId);
            body.put("mchid", merchant.mchId);
            body.put("description", StringUtils.hasText(description) ? description : "门店消费");
            body.put("out_trade_no", outTradeNo);
            body.put("notify_url", merchant.notifyUrl);
            body.put("time_expire", new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX").format(expiresAt));
            Map<String, Object> amount = new HashMap<>();
            amount.put("total", amountFen);
            amount.put("currency", "CNY");
            body.put("amount", amount);
            String json = objectMapper.writeValueAsString(body);
            String path = "/v3/pay/transactions/native";
            ResponseEntity<String> httpResponse = restTemplate.postForEntity(API + path,
                    new HttpEntity<>(json, headers("POST", path, json, merchant)), String.class);
            String response = verifiedBody(httpResponse, merchant);
            @SuppressWarnings("unchecked") Map<String, Object> parsed = objectMapper.readValue(response, Map.class);
            String codeUrl = parsed.get("code_url") == null ? null : String.valueOf(parsed.get("code_url"));
            if (!StringUtils.hasText(codeUrl)) throw new IllegalStateException("微信未返回 code_url");
            return new CreateResult(codeUrl);
        } catch (Exception e) {
            throw apiException("微信Native下单失败", e);
        }
    }

    /** JSAPI 下单使用与 Native 相同的商户版本解析、响应验签和失败分类。 */
    public JsapiCreateResult createJsapi(Integer shopId, String merchantId, Long configId, Integer configVersion,
                                         String outTradeNo, Integer amountFen, String openid,
                                         String description, Date expiresAt) {
        try {
            WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion);
            Map<String, Object> body = new HashMap<>();
            body.put("appid", merchant.appId);
            body.put("mchid", merchant.mchId);
            body.put("description", StringUtils.hasText(description) ? description : "门店消费");
            body.put("out_trade_no", outTradeNo);
            body.put("notify_url", merchant.notifyUrl);
            body.put("time_expire", new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX").format(expiresAt));
            Map<String, Object> amount = new HashMap<>();
            amount.put("total", amountFen);
            amount.put("currency", "CNY");
            body.put("amount", amount);
            body.put("payer", Collections.singletonMap("openid", openid));
            String json = objectMapper.writeValueAsString(body);
            String path = "/v3/pay/transactions/jsapi";
            ResponseEntity<String> httpResponse = restTemplate.postForEntity(API + path,
                    new HttpEntity<>(json, headers("POST", path, json, merchant)), String.class);
            String response = verifiedBody(httpResponse, merchant);
            @SuppressWarnings("unchecked") Map<String, Object> parsed = objectMapper.readValue(response, Map.class);
            String prepayId = parsed.get("prepay_id") == null ? null : String.valueOf(parsed.get("prepay_id"));
            if (!StringUtils.hasText(prepayId)) throw new IllegalStateException("微信未返回 prepay_id");
            Map<String, String> payParams = WechatPayV3Crypto.buildMiniProgramPayParams(
                    prepayId, merchant.appId, merchant.signer, merchant.privateKey);
            return new JsapiCreateResult(prepayId, payParams);
        } catch (Exception e) {
            throw apiException("微信JSAPI下单失败", e);
        }
    }

    public Map<String, String> buildJsapiPayParams(Integer shopId, String merchantId,
                                                    Long configId, Integer configVersion, String prepayId) {
        try {
            WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion);
            return WechatPayV3Crypto.buildMiniProgramPayParams(
                    prepayId, merchant.appId, merchant.signer, merchant.privateKey);
        } catch (Exception e) {
            throw apiException("微信JSAPI支付参数签名失败", e);
        }
    }

    public QueryResult query(Integer shopId, String merchantId, String outTradeNo) {
        return query(shopId, merchantId, null, null, outTradeNo);
    }

    public QueryResult query(Integer shopId, String merchantId, Long configId, Integer configVersion, String outTradeNo) {
        try {
            WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion);
            String path = "/v3/pay/transactions/out-trade-no/" + outTradeNo + "?mchid=" + merchant.mchId;
            ResponseEntity<String> response = restTemplate.exchange(API + path, HttpMethod.GET,
                    new HttpEntity<>(headers("GET", path, "", merchant)), String.class);
            String body = verifiedBody(response, merchant);
            @SuppressWarnings("unchecked") Map<String, Object> parsed = objectMapper.readValue(body, Map.class);
            return QueryResult.from(parsed);
        } catch (Exception e) {
            throw apiException("微信Native查单失败", e);
        }
    }

    public void close(Integer shopId, String merchantId, String outTradeNo) {
        close(shopId, merchantId, null, null, outTradeNo);
    }

    public void close(Integer shopId, String merchantId, Long configId, Integer configVersion, String outTradeNo) {
        try {
            WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion);
            String path = "/v3/pay/transactions/out-trade-no/" + outTradeNo + "/close";
            String json = objectMapper.writeValueAsString(Collections.singletonMap("mchid", merchant.mchId));
            ResponseEntity<String> response = restTemplate.exchange(API + path, HttpMethod.POST,
                    new HttpEntity<>(json, headers("POST", path, json, merchant)), String.class);
            verifiedBody(response, merchant);
        } catch (Exception e) {
            throw apiException("微信Native关单失败", e);
        }
    }

    private WechatMerchantKeyStore.ResolvedMerchant merchant(Integer shopId, String merchantId,
                                                               Long configId, Integer configVersion) {
        WechatMerchantKeyStore.ResolvedMerchant merchant = configId != null && configVersion != null
                ? merchantKeyStore.resolveBound(configId, configVersion, shopId)
                : merchantKeyStore.resolveForPay(shopId, merchantId, null);
        if (merchant == null || merchant.privateKey == null || !StringUtils.hasText(merchant.mchId)
                || !StringUtils.hasText(merchant.serialNo) || !StringUtils.hasText(merchant.appId)
                || !StringUtils.hasText(merchant.notifyUrl) || !StringUtils.hasText(merchant.platformPubKeyId)
                || merchant.wechatPublicKey == null) {
            throw new IllegalStateException("微信支付商户配置不完整");
        }
        if (merchant.payAuthAudit != null
                && (Boolean.FALSE.equals(merchant.payAuthAudit.serialMatchesCert)
                || Boolean.TRUE.equals(merchant.payAuthAudit.certExpired))) {
            throw new IllegalStateException("微信支付商户证书序列号不匹配或证书已过期");
        }
        return merchant;
    }

    private String verifiedBody(ResponseEntity<String> response,
                                WechatMerchantKeyStore.ResolvedMerchant merchant) throws Exception {
        if (response == null) throw new IllegalStateException("微信响应为空");
        HttpHeaders responseHeaders = response.getHeaders();
        String platformKeyId = responseHeaders.getFirst("Wechatpay-Serial");
        String timestamp = responseHeaders.getFirst("Wechatpay-Timestamp");
        String nonce = responseHeaders.getFirst("Wechatpay-Nonce");
        String signature = responseHeaders.getFirst("Wechatpay-Signature");
        if (!merchant.platformPubKeyId.equals(platformKeyId)) {
            throw new SecurityException("微信响应平台公钥ID不匹配");
        }
        if (!StringUtils.hasText(timestamp) || !StringUtils.hasText(nonce)
                || !StringUtils.hasText(signature)) {
            throw new SecurityException("微信响应签名头不完整");
        }
        long responseEpoch;
        try {
            responseEpoch = Long.parseLong(timestamp);
        } catch (RuntimeException invalidTimestamp) {
            throw new SecurityException("微信响应时间戳无效", invalidTimestamp);
        }
        long nowEpoch = System.currentTimeMillis() / 1000;
        if (responseEpoch < nowEpoch - MAX_RESPONSE_AGE_SECONDS
                || responseEpoch > nowEpoch + MAX_RESPONSE_AGE_SECONDS) {
            throw new SecurityException("微信响应已过期");
        }
        String body = response.getBody() == null ? "" : response.getBody();
        if (!WechatPayV3Crypto.verifyNotifySignature(
                body, timestamp, nonce, signature, merchant.wechatPublicKey)) {
            throw new SecurityException("微信响应签名无效");
        }
        return body;
    }

    private HttpHeaders headers(String method, String path, String body,
                                WechatMerchantKeyStore.ResolvedMerchant merchant) throws Exception {
        String nonce = WechatPayV3Crypto.generateNonceStr();
        String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
        String signature = WechatPayV3Crypto.signApiRequest(method, path, timestamp, nonce, body, merchant.privateKey);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setAccept(Collections.singletonList(MediaType.APPLICATION_JSON));
        headers.set("Authorization", String.format(
                "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                merchant.mchId, nonce, timestamp, signature, merchant.serialNo));
        if (StringUtils.hasText(merchant.platformPubKeyId)) headers.set("Wechatpay-Serial", merchant.platformPubKeyId);
        return headers;
    }

    private ApiException apiException(String message, Exception cause) {
        if (!(cause instanceof HttpStatusCodeException)) {
            return new ApiException(message, cause, FailureType.UNCERTAIN, null, null, null, null);
        }
        HttpStatusCodeException httpError = (HttpStatusCodeException) cause;
        int status = httpError.getRawStatusCode();
        String wechatCode = null;
        String wechatMessage = null;
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> errorBody = objectMapper.readValue(httpError.getResponseBodyAsString(), Map.class);
            wechatCode = safeText(errorBody.get("code"), 64);
            wechatMessage = safeText(errorBody.get("message"), 160);
        } catch (Exception ignored) {
            // 非 JSON 错误页不得原样进入日志或 API 响应。
        }
        String requestId = safeText(httpError.getResponseHeaders() == null ? null
                : httpError.getResponseHeaders().getFirst("Request-ID"), 128);
        FailureType type = status >= 400 && status < 500
                ? FailureType.REJECTED : FailureType.UNCERTAIN;
        return new ApiException(message, cause, type, status, wechatCode, wechatMessage, requestId);
    }

    private static String safeText(Object value, int maxLength) {
        if (value == null) return null;
        String text = String.valueOf(value).replaceAll("[\\r\\n\\t\\p{Cntrl}]", " ").trim();
        if (!StringUtils.hasText(text)) return null;
        return text.length() <= maxLength ? text : text.substring(0, maxLength);
    }

    public static class CreateResult {
        public final String codeUrl;
        public CreateResult(String codeUrl) { this.codeUrl = codeUrl; }
    }

    public static class JsapiCreateResult {
        public final String prepayId;
        public final Map<String, String> payParams;
        public JsapiCreateResult(String prepayId, Map<String, String> payParams) {
            this.prepayId = prepayId;
            this.payParams = payParams;
        }
    }

    public static class QueryResult {
        public String tradeState;
        public String transactionId;
        public String successTime;
        public String tradeType;
        public String appId;
        public String mchId;
        public Integer total;
        public String payerOpenid;

        @SuppressWarnings("unchecked")
        static QueryResult from(Map<String, Object> map) {
            QueryResult r = new QueryResult();
            r.tradeState = text(map.get("trade_state"));
            r.transactionId = text(map.get("transaction_id"));
            r.successTime = text(map.get("success_time"));
            r.tradeType = text(map.get("trade_type"));
            r.appId = text(map.get("appid"));
            r.mchId = text(map.get("mchid"));
            Object amount = map.get("amount");
            if (amount instanceof Map && ((Map<?, ?>) amount).get("total") instanceof Number) {
                r.total = ((Number) ((Map<?, ?>) amount).get("total")).intValue();
            }
            Object payer = map.get("payer");
            if (payer instanceof Map) r.payerOpenid = text(((Map<?, ?>) payer).get("openid"));
            return r;
        }

        public static QueryResult success(String transactionId, int total, String successTime) {
            QueryResult r = new QueryResult();
            r.tradeState = "SUCCESS"; r.tradeType = "NATIVE"; r.transactionId = transactionId;
            r.total = total; r.successTime = successTime; return r;
        }

        public Map<String, Object> asPaymentResult(String outTradeNo) {
            Map<String, Object> map = new HashMap<>();
            map.put("out_trade_no", outTradeNo); map.put("transaction_id", transactionId);
            map.put("trade_state", tradeState); map.put("trade_type", tradeType);
            map.put("success_time", successTime); map.put("appid", appId); map.put("mchid", mchId);
            map.put("amount", Collections.singletonMap("total", total));
            if (StringUtils.hasText(payerOpenid)) map.put("payer", Collections.singletonMap("openid", payerOpenid));
            return map;
        }
        private static String text(Object value) { return value == null ? null : String.valueOf(value); }
    }

    public enum FailureType { REJECTED, UNCERTAIN }

    public static class ApiException extends RuntimeException {
        public final FailureType failureType;
        public final Integer httpStatus;
        public final String wechatCode;
        public final String wechatMessage;
        public final String requestId;

        public ApiException(String message, Throwable cause) {
            this(message, cause, FailureType.UNCERTAIN, null, null, null, null);
        }

        public ApiException(String message, Throwable cause, FailureType failureType,
                            Integer httpStatus, String wechatCode, String wechatMessage, String requestId) {
            super(message, cause);
            this.failureType = failureType;
            this.httpStatus = httpStatus;
            this.wechatCode = wechatCode;
            this.wechatMessage = wechatMessage;
            this.requestId = requestId;
        }

        public boolean isDefinitiveRejection() {
            return failureType == FailureType.REJECTED;
        }

        public boolean isOrderNonexistentOrClosed() {
            if ("ORDER_NOT_EXIST".equalsIgnoreCase(wechatCode)
                    || "ORDERNOTEXIST".equalsIgnoreCase(wechatCode)
                    || "ORDER_CLOSED".equalsIgnoreCase(wechatCode)
                    || "ORDERCLOSED".equalsIgnoreCase(wechatCode)) {
                return true;
            }
            if (httpStatus != null && httpStatus == 404) {
                return true;
            }
            return false;
        }
    }
}
