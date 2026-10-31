package com.lanf.integration.remote;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.integration.config.ZsqProperties;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.dto.*;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.List;
import java.util.Map;

/**
 * 调用真省钱开放平台 HTTP API（zsq.wlhulian.com/api）。
 */
@Component
public class ZsqRemoteClient {

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final ZsqProperties properties;

    public ZsqRemoteClient(@Qualifier("zsqRestTemplate") RestTemplate zsqRestTemplate,
                           @Qualifier("zsqObjectMapper") ObjectMapper zsqObjectMapper,
                           ZsqProperties properties) {
        this.restTemplate = zsqRestTemplate;
        this.objectMapper = zsqObjectMapper;
        this.properties = properties;
    }

    public ZsqLoginTokenData merchantLogin(ZsqLoginRequest request) {
        return post("/store/staff/login", request, new TypeReference<ZsqApiResponse<ZsqLoginTokenData>>() {})
                .getData();
    }

    public ZsqLoginTokenData partnerLogin(ZsqLoginRequest request) {
        return post("/pt/app/login", request, new TypeReference<ZsqApiResponse<ZsqLoginTokenData>>() {})
                .getData();
    }

    public Map<String, Object> merchantInfo(String authorization) {
        return get("/store/staff/info", authorization, new TypeReference<ZsqApiResponse<Map<String, Object>>>() {})
                .getData();
    }

    public List<ZsqShopAddress> listShopAddresses(String authorization) {
        return get("/open/order/address", authorization, new TypeReference<ZsqApiResponse<List<ZsqShopAddress>>>() {})
                .getData();
    }

    public List<ZsqAddressTip> addressInputTips(String authorization, String city, String keywords) {
        URI uri = UriComponentsBuilder.fromHttpUrl(properties.getApiBase())
                .path("/address/v2/input-tips")
                .queryParam("city", city)
                .queryParam("keywords", keywords)
                .build()
                .encode()
                .toUri();
        return exchange(uri, HttpMethod.GET, null, authorization,
                new TypeReference<ZsqApiResponse<List<ZsqAddressTip>>>() {}).getData();
    }

    public ZsqCreateOrderResult createTakeawayOrder(String authorization, ZsqCreateOrderPayload payload) {
        return post("/open/order/create", payload, authorization,
                new TypeReference<ZsqApiResponse<ZsqCreateOrderResult>>() {}).getData();
    }

    public void markAddressUsed(String authorization, ZsqCreateOrderPayload payload) {
        Map<String, Object> body = objectMapper.convertValue(payload, new TypeReference<Map<String, Object>>() {});
        body.put("addressId", payload.getFromAddressId());
        post("/delivery/address/update/use/address", body, authorization,
                new TypeReference<ZsqApiResponse<Object>>() {});
    }

    /** 外卖订单详情（含骑手坐标、配送状态等）。 */
    public Map<String, Object> getOpenOrderDetail(String authorization, long openOrderId) {
        return get("/open/order/" + openOrderId, authorization,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {}).getData();
    }

    /** 配送询价。 */
    public List<ZsqDeliveryBillingChannel> quoteDelivery(String authorization, Map<String, Object> billingParam) {
        return post("/delivery/order/billing", billingParam, authorization,
                new TypeReference<ZsqApiResponse<List<ZsqDeliveryBillingChannel>>>() {}).getData();
    }

    /** 发起配送（保存并发单）。 */
    public Map<String, Object> dispatchDelivery(String authorization, Map<String, Object> dispatchBody) {
        return post("/delivery/order/create", dispatchBody, authorization,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {}).getData();
    }

    /** 配送状态时间线（含轨迹节点）。 */
    public List<Map<String, Object>> getDeliveryStatusTimeline(String authorization, long openOrderId) {
        return get("/open/order/delivery/status/new/" + openOrderId, authorization,
                new TypeReference<ZsqApiResponse<List<Map<String, Object>>>>() {}).getData();
    }

    /** 订单操作/配送轨迹日志（用于以最新有效记录判断真实配送状态）。 */
    public List<Map<String, Object>> getOpenOrderLog(String authorization, long openOrderId) {
        return get("/open/order/log/" + openOrderId + "?id=" + openOrderId, authorization,
                new TypeReference<ZsqApiResponse<List<Map<String, Object>>>>() {}).getData();
    }

    /** 取消前提示（含责任费文案，已发配送时）。 */
    public Map<String, Object> getDeliveryCancelPrompt(String authorization, long openOrderId) {
        return getAllowNull("/delivery/order/cancelPrompt/" + openOrderId, authorization,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {});
    }

    /** 取消外卖 open 订单（未发配送或兜底）。 */
    public Map<String, Object> cancelOpenOrder(String authorization, long openOrderId) {
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("id", openOrderId);
        return postAllowNull("/open/order/cancel", body, authorization,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {});
    }

    /** 取消配送单（v2，已发配送优先）。 */
    public Map<String, Object> cancelDeliveryOrderV2(String authorization, Map<String, Object> body) {
        return postAllowNull("/delivery/order/cancel/v2", body, authorization,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {});
    }

    /** 取消配送单（旧版，需 parentOrderId）。 */
    public Map<String, Object> cancelDeliveryOrder(String authorization, Map<String, Object> body) {
        return postAllowNull("/delivery/order/cancel", body, authorization,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {});
    }

    private <T> T getAllowNull(String path, String authorization, TypeReference<ZsqApiResponse<T>> type) {
        ZsqApiResponse<T> api = getRaw(path, authorization, type);
        ensureCode200(api, path);
        return api.getData();
    }

    private <T, B> T postAllowNull(String path, B body, String authorization,
                                   TypeReference<ZsqApiResponse<T>> type) {
        ZsqApiResponse<T> api = postRaw(path, body, authorization, type);
        ensureCode200(api, path);
        return api.getData();
    }

    private <T> ZsqApiResponse<T> getRaw(String path, String authorization, TypeReference<ZsqApiResponse<T>> type) {
        URI uri = URI.create(joinUrl(path));
        return exchange(uri, HttpMethod.GET, null, authorization, type);
    }

    private <T, B> ZsqApiResponse<T> postRaw(String path, B body, String authorization,
                                             TypeReference<ZsqApiResponse<T>> type) {
        URI uri = URI.create(joinUrl(path));
        return exchange(uri, HttpMethod.POST, body, authorization, type);
    }

    private void ensureCode200(ZsqApiResponse<?> api, String path) {
        if (api == null) {
            throw new ZsqApiException("真省钱接口无响应体: " + path);
        }
        if (api.getCode() != 200) {
            throw new ZsqApiException(api.getCode(), api.getMessage(), api.getTraceId());
        }
    }

    private <T> ZsqApiResponse<T> get(String path, String authorization, TypeReference<ZsqApiResponse<T>> type) {
        URI uri = URI.create(joinUrl(path));
        return exchange(uri, HttpMethod.GET, null, authorization, type);
    }

    private <T, B> ZsqApiResponse<T> post(String path, B body, TypeReference<ZsqApiResponse<T>> type) {
        return post(path, body, null, type);
    }

    private <T, B> ZsqApiResponse<T> post(String path, B body, String authorization,
                                          TypeReference<ZsqApiResponse<T>> type) {
        URI uri = URI.create(joinUrl(path));
        return exchange(uri, HttpMethod.POST, body, authorization, type);
    }

    private <T, B> ZsqApiResponse<T> exchange(URI uri, HttpMethod method, B body, String authorization,
                                              TypeReference<ZsqApiResponse<T>> type) {
        HttpHeaders headers = buildHeaders(authorization);
        HttpEntity<B> entity = body == null ? new HttpEntity<>(headers) : new HttpEntity<>(body, headers);
        ResponseEntity<String> response = restTemplate.exchange(uri, method, entity, String.class);
        ZsqApiResponse<T> api = ZsqApiResponseParser.parse(objectMapper, response.getBody(), type);
        if (api == null) {
            throw new ZsqApiException("真省钱接口无响应体: " + uri);
        }
        if (api.getCode() != 200) {
            throw new ZsqApiException(api.getCode(), api.getMessage(), api.getTraceId());
        }
        return api;
    }

    private HttpHeaders buildHeaders(String authorization) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("requestType", "pc");
        if (authorization != null && !authorization.trim().isEmpty()) {
            headers.set(HttpHeaders.AUTHORIZATION, authorization);
        }
        return headers;
    }

    private String joinUrl(String path) {
        String base = properties.getApiBase();
        if (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        if (!path.startsWith("/")) {
            path = "/" + path;
        }
        return base + path;
    }
}
