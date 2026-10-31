package com.lanf.payment.channel.wechat;

import org.apache.http.client.config.RequestConfig;
import org.apache.http.conn.ssl.SSLConnectionSocketFactory;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.ssl.SSLContexts;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** 微信支付 V2 付款码支付、查单与撤销客户端。 */
@Component
public class WechatMicropayApiClient {
    private static final String API = "https://api.mch.weixin.qq.com";
    @Autowired private WechatMerchantKeyStore merchantKeyStore;
    @Autowired private RestTemplate restTemplate;

    public Result pay(Integer shopId, String merchantId, String outTradeNo, int amountFen,
                      String authCode, String terminalId, String clientIp) {
        return pay(shopId, merchantId, null, null, outTradeNo, amountFen, authCode, terminalId, clientIp);
    }

    public Result pay(Integer shopId, String merchantId, Long configId, Integer configVersion,
                      String outTradeNo, int amountFen, String authCode, String terminalId, String clientIp) {
        WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion, false);
        Map<String, String> params = base(merchant);
        params.put("body", "门店消费");
        params.put("out_trade_no", outTradeNo);
        params.put("total_fee", String.valueOf(amountFen));
        params.put("spbill_create_ip", clientIp);
        params.put("auth_code", authCode);
        if (StringUtils.hasText(terminalId)) params.put("device_info", terminalId);
        return request(restTemplate, "/pay/micropay", params, merchant, outTradeNo);
    }

    public Result query(Integer shopId, String merchantId, String outTradeNo) {
        return query(shopId, merchantId, null, null, outTradeNo);
    }

    public Result query(Integer shopId, String merchantId, Long configId, Integer configVersion, String outTradeNo) {
        WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion, false);
        Map<String, String> params = base(merchant);
        params.put("out_trade_no", outTradeNo);
        return request(restTemplate, "/pay/orderquery", params, merchant, outTradeNo);
    }

    public Result reverse(Integer shopId, String merchantId, String outTradeNo) {
        return reverse(shopId, merchantId, null, null, outTradeNo);
    }

    public Result reverse(Integer shopId, String merchantId, Long configId, Integer configVersion, String outTradeNo) {
        WechatMerchantKeyStore.ResolvedMerchant merchant = merchant(shopId, merchantId, configId, configVersion, true);
        Map<String, String> params = base(merchant);
        params.put("out_trade_no", outTradeNo);
        try (CloseableHttpClient http = mtlsClient(merchant)) {
            Result result = request(new RestTemplate(new HttpComponentsClientHttpRequestFactory(http)),
                    "/secapi/pay/reverse", params, merchant, outTradeNo);
            if ("SUCCESS".equals(result.resultCode)) result.tradeState = "REVERSED";
            return result;
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new ApiException("微信付款码撤销客户端证书加载失败", e);
        }
    }

    private Result request(RestTemplate template, String path, Map<String, String> params,
                           WechatMerchantKeyStore.ResolvedMerchant merchant, String expectedOutTradeNo) {
        params.put("sign", WechatPayV2Codec.sign(params, merchant.apiV2Key));
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_XML);
        headers.setAccept(Collections.singletonList(MediaType.APPLICATION_XML));
        final String xml;
        try {
            byte[] sensitiveBody = WechatPayV2Codec.toXml(params).getBytes(StandardCharsets.UTF_8);
            xml = template.postForObject(API + path, new HttpEntity<>(sensitiveBody, headers), String.class);
        } catch (RuntimeException e) {
            throw new ApiException("微信付款码接口通信失败", e);
        }
        Map<String, String> response = WechatPayV2Codec.parse(xml);
        if (!"SUCCESS".equals(response.get("return_code"))) {
            throw new ApiException("微信付款码接口通信失败", null);
        }
        if (!WechatPayV2Codec.verify(response, merchant.apiV2Key)) {
            throw new ApiException("微信付款码响应签名无效", null);
        }
        if (!merchant.appId.equals(response.get("appid"))) {
            throw new ApiException("微信付款码响应 AppID 不匹配", null);
        }
        if (!merchant.mchId.equals(response.get("mch_id"))) {
            throw new ApiException("微信付款码响应商户号不匹配", null);
        }
        if (!expectedOutTradeNo.equals(response.get("out_trade_no"))) {
            throw new ApiException("微信付款码响应商户单号不匹配", null);
        }
        return Result.from(response);
    }

    private Map<String, String> base(WechatMerchantKeyStore.ResolvedMerchant merchant) {
        Map<String, String> params = new LinkedHashMap<>();
        params.put("appid", merchant.appId);
        params.put("mch_id", merchant.mchId);
        params.put("nonce_str", UUID.randomUUID().toString().replace("-", ""));
        params.put("sign_type", "HMAC-SHA256");
        return params;
    }

    private WechatMerchantKeyStore.ResolvedMerchant merchant(Integer shopId, String merchantId,
                                                               Long configId, Integer configVersion,
                                                               boolean requireCert) {
        WechatMerchantKeyStore.ResolvedMerchant merchant = configId != null && configVersion != null
                ? merchantKeyStore.resolveBound(configId, configVersion, shopId)
                : merchantKeyStore.resolveForPay(shopId, merchantId, null);
        if (merchant == null || !StringUtils.hasText(merchant.appId) || !StringUtils.hasText(merchant.mchId)
                || merchant.apiV2Key == null || merchant.apiV2Key.length() != 32
                || (requireCert && !StringUtils.hasText(merchant.clientCertP12Ref))) {
            throw new IllegalStateException("微信付款码支付商户配置不完整");
        }
        return merchant;
    }

    private CloseableHttpClient mtlsClient(WechatMerchantKeyStore.ResolvedMerchant merchant) throws Exception {
        File file = new File(merchant.clientCertP12Ref);
        if (!file.isFile()) throw new IllegalStateException("微信客户端证书文件不存在");
        char[] password = merchant.mchId.toCharArray();
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        try (FileInputStream in = new FileInputStream(file)) { keyStore.load(in, password); }
        SSLContext sslContext = SSLContexts.custom().loadKeyMaterial(keyStore, password).build();
        RequestConfig config = RequestConfig.custom().setConnectTimeout(5000)
                .setConnectionRequestTimeout(5000).setSocketTimeout(10000).build();
        return HttpClients.custom()
                .setSSLSocketFactory(new SSLConnectionSocketFactory(sslContext)).setDefaultRequestConfig(config).build();
    }

    public static final class Result {
        public String resultCode;
        public String errCode;
        public String tradeState;
        public String transactionId;
        public Integer totalFee;
        public String timeEnd;
        public String tradeType;
        public String appId;
        public String mchId;

        static Result from(Map<String, String> map) {
            Result r = new Result();
            r.resultCode = map.get("result_code"); r.errCode = map.get("err_code");
            r.tradeState = map.get("trade_state"); r.transactionId = map.get("transaction_id");
            r.timeEnd = map.get("time_end"); r.tradeType = map.get("trade_type");
            r.appId = map.get("appid"); r.mchId = map.get("mch_id");
            if (StringUtils.hasText(map.get("total_fee"))) r.totalFee = Integer.valueOf(map.get("total_fee"));
            if ("SUCCESS".equals(r.resultCode) && !StringUtils.hasText(r.tradeState)) r.tradeState = "SUCCESS";
            if ("USERPAYING".equals(r.errCode)) r.tradeState = "USERPAYING";
            return r;
        }

        public static Result pendingUserPaying() { Result r = new Result(); r.resultCode = "FAIL"; r.errCode = "USERPAYING"; r.tradeState = "USERPAYING"; return r; }
        public static Result success(String transactionId, int totalFee, String timeEnd) {
            Result r = new Result(); r.resultCode = "SUCCESS"; r.tradeState = "SUCCESS";
            r.transactionId = transactionId; r.totalFee = totalFee; r.timeEnd = timeEnd; r.tradeType = "MICROPAY"; return r;
        }
        public boolean success() { return "SUCCESS".equals(resultCode) && "SUCCESS".equals(tradeState); }
        public boolean userPaying() { return "USERPAYING".equals(errCode) || "USERPAYING".equals(tradeState); }
        public boolean unknown() { return "SYSTEMERROR".equals(errCode) || "BANKERROR".equals(errCode); }
        public Map<String, Object> asPaymentResult(String outTradeNo) {
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("out_trade_no", outTradeNo); map.put("transaction_id", transactionId);
            map.put("trade_state", tradeState); map.put("trade_type", "MICROPAY");
            map.put("success_time", timeEnd); map.put("appid", appId); map.put("mchid", mchId);
            map.put("amount", Collections.singletonMap("total", totalFee));
            return map;
        }
    }

    public static class ApiException extends RuntimeException {
        public ApiException(String message, Throwable cause) { super(message, cause); }
    }
}
