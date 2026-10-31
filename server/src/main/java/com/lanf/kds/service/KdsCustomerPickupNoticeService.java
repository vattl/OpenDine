package com.lanf.kds.service;

import com.lanf.entity.Order;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestTemplate;

import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * KDS 全部菜品完成自动通知客户取餐服务。
 * <p>
 * 当工单整单划菜完成（KdsOrderStatus.ALL_DONE）时触发：
 * 1. 幂等更新 t_order.notice = 1（防止重复触达）；
 * 2. 通过 DishMenuPushService 向 C 端点餐小程序 /ws/menu 广播 meal_pickup_ready；
 * 3. 通过 KdsPushService 向 KDS / 收银总览广播 order_notice；
 * 4. 若订单关联 openid 且配置了取餐通知模板，向微信下发订阅消息。
 * </p>
 */
@Service
public class KdsCustomerPickupNoticeService {

    private static final Logger log = LoggerFactory.getLogger(KdsCustomerPickupNoticeService.class);

    @Autowired
    private IOrderService orderService;
    @Autowired
    private DishMenuPushService dishMenuPushService;
    @Autowired
    private KdsPushService kdsPushService;
    @Autowired(required = false)
    private UnifiedNotificationService unifiedNotificationService;
    @Autowired(required = false)
    private RestTemplate restTemplate;
    @Autowired(required = false)
    private com.lanf.service.IWechatSubscribeQuotaService subscribeQuotaService;

    public void setUnifiedNotificationService(UnifiedNotificationService unifiedNotificationService) {
        this.unifiedNotificationService = unifiedNotificationService;
    }

    @Value("${weixin.subscribe-templates.pickup-notice:}")
    private String pickupNoticeTemplateId;
    @Value("${weixin.appid:}")
    private String appid;
    @Value("${weixin.secret:}")
    private String appsecret;

    private final Map<String, TokenEntry> tokenCache = new ConcurrentHashMap<>();

    private static class TokenEntry {
        final String token;
        final long expireAt;

        TokenEntry(String token, long ttlMillis) {
            this.token = token;
            this.expireAt = System.currentTimeMillis() + ttlMillis;
        }

        boolean isValid() {
            return token != null && System.currentTimeMillis() < expireAt;
        }
    }

    /**
     * 全部菜品制作并出餐完成，自动通知客户取餐。
     *
     * @param shopId  门店ID
     * @param orderId 订单ID
     * @return true 若成功触发首次通知，false 若已通知或订单不存在
     */
    public boolean notifyCustomerPickup(int shopId, int orderId) {
        Order order = orderService.getById(orderId);
        if (order == null) {
            log.warn("[kds-notice] 订单不存在，无法触发取餐通知: shopId={}, orderId={}", shopId, orderId);
            return false;
        }
        // 幂等防重：若已通知，不再重复下发
        if (Integer.valueOf(1).equals(order.getNotice())) {
            log.debug("[kds-notice] 订单已通知过取餐，忽略重复触发: orderId={}, orderNo={}", orderId, order.getOrder_no());
            return false;
        }

        order.setNotice(1);
        orderService.updateById(order);
        log.info("[kds-notice] 订单全部菜品出餐完成，自动触发客户取餐通知: shopId={}, orderId={}, orderNo={}",
                shopId, orderId, order.getOrder_no());

        String pickupCode = resolvePickupCode(order);

        // 1. 推送点餐端小程序 WebSocket /ws/menu 及统一实时通道 /ws/v1/notify
        try {
            dishMenuPushService.notifyMealPickupReady(
                    shopId, orderId, order.getOrder_no(),
                    order.getTable_number(), order.getDineInOrTakeOut(), pickupCode);
        } catch (Exception ex) {
            log.warn("[kds-notice] 推送 /ws/menu 取餐消息异常 orderId={}: {}", orderId, ex.getMessage());
        }
        if (unifiedNotificationService != null && StringUtils.hasText(order.getOpenid())) {
            try {
                unifiedNotificationService.publishCustomerOrderPickupReady(order, pickupCode);
            } catch (Exception ex) {
                log.warn("[kds-notice] 推送顾客专属取餐通知异常 orderId={}: {}", orderId, ex.getMessage());
            }
        }

        // 2. 推送 KDS 及收银工作台广播
        try {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("order_id", orderId);
            payload.put("order_no", order.getOrder_no());
            payload.put("table_number", order.getTable_number());
            payload.put("dine_in_or_take_out", order.getDineInOrTakeOut());
            payload.put("pickup_code", pickupCode);
            payload.put("notice", 1);
            kdsPushService.orderStatusChanged(shopId, null, KdsOrderStatus.ALL_DONE, payload);
        } catch (Exception ex) {
            log.warn("[kds-notice] 推送 KDS 取餐消息异常 orderId={}: {}", orderId, ex.getMessage());
        }

        // 3. 发送微信订阅消息（异步/容错）
        if (StringUtils.hasText(order.getOpenid())) {
            try {
                sendWechatPickupSubscribeMessage(order, pickupCode);
            } catch (Exception ex) {
                log.warn("[kds-notice] 发送微信取餐订阅消息异常 orderId={}: {}", orderId, ex.getMessage());
            }
        }
        return true;
    }

    private static String resolvePickupCode(Order order) {
        if (order == null) {
            return "";
        }
        if (order.getId() != null) {
            return String.valueOf(order.getId());
        }
        if (StringUtils.hasText(order.getOrder_no())) {
            return order.getOrder_no();
        }
        return "";
    }

    private void sendWechatPickupSubscribeMessage(Order order, String pickupCode) {
        String effectiveTemplateId = pickupNoticeTemplateId;
        if (subscribeQuotaService != null) {
            com.lanf.entity.SubscribeSceneTemplate t = subscribeQuotaService.getActiveTemplateByScene("ORDER_PICKUP");
            if (t != null && StringUtils.hasText(t.getTemplate_id())) {
                effectiveTemplateId = t.getTemplate_id().trim();
            }
        }

        if (!StringUtils.hasText(effectiveTemplateId) || restTemplate == null) {
            return;
        }
        String accessToken = getAccessToken();
        if (!StringUtils.hasText(accessToken)) {
            log.debug("[kds-notice] 无法获取微信 access_token，跳过订阅消息下发");
            return;
        }

        long startMs = System.currentTimeMillis();
        String url = "https://api.weixin.qq.com/cgi-bin/message/subscribe/send?access_token=" + accessToken;
        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("touser", order.getOpenid());
        requestBody.put("template_id", effectiveTemplateId);
        requestBody.put("page", "packageOther/order-details/details?order_no=" + order.getOrder_no());

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("character_string1", Collections.singletonMap("value", slice(pickupCode, 32)));
        data.put("phrase2", Collections.singletonMap("value", "已出餐"));
        data.put("thing3", Collections.singletonMap("value", slice("餐品已全部制作完成，请前往取餐", 20)));
        data.put("thing4", Collections.singletonMap("value", slice(StringUtils.hasText(order.getTable_number()) ? "桌号: " + order.getTable_number() : "到店凭取餐号取餐", 20)));

        requestBody.put("data", data);
        requestBody.put("miniprogram_state", "formal");
        requestBody.put("lang", "zh_CN");

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

        int errcode = -1;
        String errmsg = "";
        try {
            Map<?, ?> response = restTemplate.postForObject(url, entity, Map.class);
            if (response != null && response.get("errcode") instanceof Number) {
                errcode = ((Number) response.get("errcode")).intValue();
                errmsg = response.get("errmsg") != null ? response.get("errmsg").toString() : "";
            }
            if (errcode == 0) {
                log.info("[kds-notice] 微信取餐订阅消息下发成功 order_no={}", order.getOrder_no());
            } else {
                log.warn("[kds-notice] 微信取餐订阅消息响应: errcode={}, errmsg={}", errcode, errmsg);
            }
        } catch (Exception e) {
            log.warn("[kds-notice] 微信取餐订阅消息调用异常 order_no={}: {}", order.getOrder_no(), e.getMessage());
            errmsg = e.getMessage();
        } finally {
            long durationMs = System.currentTimeMillis() - startMs;
            if (subscribeQuotaService != null) {
                subscribeQuotaService.handleSendResult(
                        order.getOpenid(),
                        "ORDER_PICKUP",
                        effectiveTemplateId,
                        errcode,
                        errmsg,
                        order.getOrder_no(),
                        durationMs,
                        "pickupCode=" + pickupCode + ", table=" + order.getTable_number()
                );
            }
        }
    }

    private String getAccessToken() {
        TokenEntry entry = tokenCache.get("access_token");
        if (entry != null && entry.isValid()) {
            return entry.token;
        }
        if (!StringUtils.hasText(appid) || !StringUtils.hasText(appsecret) || restTemplate == null) {
            return null;
        }
        try {
            String url = "https://api.weixin.qq.com/cgi-bin/stable_token";
            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("grant_type", "client_credential");
            requestBody.put("appid", appid);
            requestBody.put("secret", appsecret);
            requestBody.put("force_refresh", false);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            Map<?, ?> resp = restTemplate.postForObject(url, entity, Map.class);
            if (resp != null && resp.get("access_token") != null) {
                String token = (String) resp.get("access_token");
                Number expiresIn = resp.get("expires_in") instanceof Number ? (Number) resp.get("expires_in") : 7200;
                long ttl = Math.max(300, expiresIn.longValue() - 300) * 1000L;
                tokenCache.put("access_token", new TokenEntry(token, ttl));
                return token;
            }
        } catch (Exception ex) {
            log.warn("[kds-notice] 获取微信 access_token 失败: {}", ex.getMessage());
        }
        return null;
    }

    private static String slice(String val, int maxLen) {
        if (val == null) {
            return "";
        }
        return val.length() <= maxLen ? val : val.substring(0, maxLen);
    }
}
