package com.lanf.notify.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.SystemConfigMapper;
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

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 新优惠券到账离线微信订阅消息触达服务。
 * 当 C 端用户不在线（无活跃 WebSocket 连接）且系统配置了优惠券到账订阅消息模板时自动触发。
 */
@Service
public class WechatCouponSubscribePushService {

    private static final Logger log = LoggerFactory.getLogger(WechatCouponSubscribePushService.class);

    public static final String CONFIG_KEY_COUPON_TEMPLATE = "weixin.subscribeTemplates.couponGranted";
    public static final String CONFIG_KEY_COUPON_EXPIRING_TEMPLATE = "weixin.subscribeTemplates.couponExpiring";

    private final SystemConfigMapper systemConfigMapper;
    private final RestTemplate restTemplate;

    @Value("${weixin.appid:}")
    private String appid;

    @Value("${weixin.secret:}")
    private String appsecret;

    @Value("${weixin.subscribe-templates.coupon-granted:}")
    private String defaultCouponGrantedTemplateId;

    @Value("${weixin.subscribe-templates.coupon-expiring:}")
    private String defaultCouponExpiringTemplateId;

    @Autowired
    public WechatCouponSubscribePushService(@Autowired(required = false) SystemConfigMapper systemConfigMapper,
                                            @Autowired(required = false) RestTemplate restTemplate) {
        this.systemConfigMapper = systemConfigMapper;
        this.restTemplate = restTemplate != null ? restTemplate : new RestTemplate();
    }

    public String resolveCouponSubscribeTemplateId() {
        if (systemConfigMapper != null) {
            try {
                SystemConfig one = systemConfigMapper.selectOne(
                        new QueryWrapper<SystemConfig>().eq("config_key", CONFIG_KEY_COUPON_TEMPLATE));
                if (one != null && StringUtils.hasText(one.getConfig_value())) {
                    return one.getConfig_value().trim();
                }
            } catch (Exception ignored) {
                // Ignore DB lookup errors in standalone tests
            }
        }
        return StringUtils.hasText(defaultCouponGrantedTemplateId) ? defaultCouponGrantedTemplateId.trim() : "";
    }

    public String resolveCouponExpiringSubscribeTemplateId() {
        if (systemConfigMapper != null) {
            try {
                SystemConfig one = systemConfigMapper.selectOne(
                        new QueryWrapper<SystemConfig>().eq("config_key", CONFIG_KEY_COUPON_EXPIRING_TEMPLATE));
                if (one != null && StringUtils.hasText(one.getConfig_value())) {
                    return one.getConfig_value().trim();
                }
            } catch (Exception ignored) {
            }
        }
        return StringUtils.hasText(defaultCouponExpiringTemplateId) ? defaultCouponExpiringTemplateId.trim() : "";
    }

    /**
     * 向离线用户发送优惠券即将过期微信订阅消息。
     */
    public boolean sendCouponExpiringSubscribeMessage(String openid, String couponName,
                                                      String discountDesc, String validUntil, String remark) {
        if (!StringUtils.hasText(openid)) {
            return false;
        }
        String templateId = resolveCouponExpiringSubscribeTemplateId();
        if (!StringUtils.hasText(templateId)) {
            templateId = resolveCouponSubscribeTemplateId();
        }
        if (!StringUtils.hasText(templateId)) {
            log.debug("[coupon-subscribe] expiring templateId not configured, skip offline push for openid={}", openid);
            return false;
        }
        String accessToken = fetchStableAccessToken();
        if (!StringUtils.hasText(accessToken)) {
            log.warn("[coupon-subscribe] unable to obtain access_token for expiring coupon openid={}", openid);
            return false;
        }
        try {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("thing1", valueMap(truncateThing(couponName != null ? couponName : "专属优惠券")));
            data.put("thing2", valueMap(truncateThing(discountDesc != null ? discountDesc : "立享优惠")));
            data.put("time3", valueMap(StringUtils.hasText(validUntil) && !"-".equals(validUntil) ? validUntil : "即将到期"));
            data.put("thing4", valueMap(truncateThing(remark != null ? remark : "优惠券即将过期，快去下单使用吧")));

            Map<String, Object> requestBody = new LinkedHashMap<>();
            requestBody.put("touser", openid.trim());
            requestBody.put("template_id", templateId);
            requestBody.put("page", "pages/index/index");
            requestBody.put("data", data);
            requestBody.put("miniprogram_state", "formal");
            requestBody.put("lang", "zh_CN");

            String url = "https://api.weixin.qq.com/cgi-bin/message/subscribe/send?access_token=" + accessToken;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            @SuppressWarnings("unchecked")
            Map<String, Object> response = restTemplate.postForObject(url, entity, Map.class);
            if (response != null && Integer.valueOf(0).equals(asInt(response.get("errcode")))) {
                log.info("[coupon-subscribe] sent expiring coupon subscribe message to openid={}, coupon={}", openid, couponName);
                return true;
            }
            log.warn("[coupon-subscribe] wechat returned non-zero for expiring coupon openid={}: {}", openid, response);
            return false;
        } catch (Exception e) {
            log.warn("[coupon-subscribe] failed to send expiring subscribe message for openid={}: {}", openid, e.getMessage());
            return false;
        }
    }

    /**
     * 向离线用户发送优惠券到账微信订阅消息（最佳努力投递，失败不阻断发券事务）。
     *
     * @return true 若成功调用微信接口且 errcode=0
     */
    public boolean sendCouponGrantedSubscribeMessage(String openid, String couponName,
                                                     String discountDesc, String validUntil, String remark) {
        if (!StringUtils.hasText(openid)) {
            return false;
        }
        String templateId = resolveCouponSubscribeTemplateId();
        if (!StringUtils.hasText(templateId)) {
            log.debug("[coupon-subscribe] templateId not configured, skip offline push for openid={}", openid);
            return false;
        }
        String accessToken = fetchStableAccessToken();
        if (!StringUtils.hasText(accessToken)) {
            log.warn("[coupon-subscribe] unable to obtain access_token for openid={}", openid);
            return false;
        }
        try {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("thing1", valueMap(truncateThing(couponName != null ? couponName : "专属优惠券")));
            data.put("thing2", valueMap(truncateThing(discountDesc != null ? discountDesc : "立享优惠")));
            data.put("time3", valueMap(StringUtils.hasText(validUntil) && !"-".equals(validUntil) ? validUntil : "长期有效"));
            data.put("thing4", valueMap(truncateThing(remark != null ? remark : "已放入您的卡包，点击立即使用")));

            Map<String, Object> requestBody = new LinkedHashMap<>();
            requestBody.put("touser", openid.trim());
            requestBody.put("template_id", templateId);
            requestBody.put("page", "pages/coupons/index");
            requestBody.put("data", data);
            requestBody.put("miniprogram_state", "formal");
            requestBody.put("lang", "zh_CN");

            String url = "https://api.weixin.qq.com/cgi-bin/message/subscribe/send?access_token=" + accessToken;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            @SuppressWarnings("unchecked")
            Map<String, Object> response = restTemplate.postForObject(url, entity, Map.class);
            if (response != null && Integer.valueOf(0).equals(asInt(response.get("errcode")))) {
                log.info("[coupon-subscribe] sent coupon subscribe message to openid={}, coupon={}", openid, couponName);
                return true;
            }
            log.warn("[coupon-subscribe] wechat returned non-zero for openid={}: {}", openid, response);
            return false;
        } catch (Exception e) {
            log.warn("[coupon-subscribe] failed to send subscribe message for openid={}: {}", openid, e.getMessage());
            return false;
        }
    }

    protected String fetchStableAccessToken() {
        if (!StringUtils.hasText(appid) || !StringUtils.hasText(appsecret)) {
            return null;
        }
        try {
            String url = "https://api.weixin.qq.com/cgi-bin/stable_token";
            Map<String, Object> body = new HashMap<>();
            body.put("grant_type", "client_credential");
            body.put("appid", appid.trim());
            body.put("secret", appsecret.trim());
            body.put("force_refresh", false);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);

            @SuppressWarnings("unchecked")
            Map<String, Object> resp = restTemplate.postForObject(url, entity, Map.class);
            if (resp != null && resp.get("access_token") instanceof String) {
                return ((String) resp.get("access_token")).trim();
            }
        } catch (Exception e) {
            log.warn("[coupon-subscribe] fetchStableAccessToken error: {}", e.getMessage());
        }
        return null;
    }

    public void setCredentialsForTest(String appid, String appsecret, String defaultTemplateId) {
        this.appid = appid;
        this.appsecret = appsecret;
        this.defaultCouponGrantedTemplateId = defaultTemplateId;
    }

    private static Map<String, Object> valueMap(String value) {
        Map<String, Object> m = new HashMap<>(2);
        m.put("value", value);
        return m;
    }

    private static String truncateThing(String input) {
        if (input == null) {
            return "";
        }
        String clean = input.trim();
        return clean.length() <= 20 ? clean : clean.substring(0, 19) + "…";
    }

    private static Integer asInt(Object o) {
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o instanceof String) {
            try {
                return Integer.parseInt(((String) o).trim());
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }
}
