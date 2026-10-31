package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.entity.ShopNotificationConfig;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.notify.service.ShopNotificationConfigService;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.realtime.UnifiedSessionRegistry;
import com.lanf.security.JwtTokenService;
import io.jsonwebtoken.Claims;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 统一实时消息通道 REST 控制器：
 * 1. 后台/收银端门店出餐超时动态阈值配置（GET/PUT /admin/shop/notification-config）
 * 2. 断线重连游标增量补偿同步（GET /cashier/notifications/sync, GET /api/v1/notifications/sync, GET /user/notifications/sync）
 * 3. 消息已读确认与多机告警联动消除（POST /cashier/notifications/ack, POST /api/v1/notifications/ack, POST /user/notifications/ack）
 */
@RestController
public class NotificationChannelController {

    private final UnifiedNotificationService notificationService;
    private final ShopNotificationConfigService configService;
    private JwtTokenService jwtTokenService;

    public NotificationChannelController(UnifiedNotificationService notificationService,
                                         ShopNotificationConfigService configService) {
        this(notificationService, configService, null);
    }

    @Autowired
    public NotificationChannelController(UnifiedNotificationService notificationService,
                                         ShopNotificationConfigService configService,
                                         @Autowired(required = false) JwtTokenService jwtTokenService) {
        this.notificationService = notificationService;
        this.configService = configService;
        this.jwtTokenService = jwtTokenService;
    }

    public void setJwtTokenService(JwtTokenService jwtTokenService) {
        this.jwtTokenService = jwtTokenService;
    }

    /**
     * 查询门店消息与出餐超时动态阈值配置。
     */
    @GetMapping("/admin/shop/notification-config")
    public R getShopNotificationConfig(@RequestParam(name = "shop_id", required = false) Integer shopIdParam,
                                       @RequestParam(name = "shopId", required = false) Integer shopIdCamel,
                                       HttpServletRequest request) {
        Integer shopId = resolveShopId(request, shopIdParam != null ? shopIdParam : shopIdCamel, null);
        ShopNotificationConfig cfg = configService.getOrDefaultConfig(shopId);
        return R.ok().put("data", configService.toConfigMap(cfg));
    }

    /**
     * 更新门店消息与出餐超时动态阈值配置（合法阈值范围：5~120 分钟）。
     */
    @PutMapping("/admin/shop/notification-config")
    public R updateShopNotificationConfig(@RequestBody Map<String, Object> body,
                                          HttpServletRequest request) {
        if (body == null) {
            return R.error(400, "请求体不能为空");
        }
        Integer shopId = resolveShopId(request, null, body);
        Boolean enabled = parseBooleanOrNull(firstNonNull(
                body.get("prep_timeout_enabled"),
                body.get("prepTimeoutEnabled"),
                body.get("enabled")));
        Integer timeoutMinutes = parseIntOrNull(firstNonNull(
                body.get("prep_timeout_minutes"),
                body.get("prepTimeoutMinutes"),
                body.get("timeout_minutes")));
        Integer repeatSeconds = parseIntOrNull(firstNonNull(
                body.get("timeout_repeat_interval_seconds"),
                body.get("timeoutRepeatIntervalSeconds"),
                body.get("repeat_interval_seconds")));
        Integer adminId = resolveAdminId(request);

        try {
            ShopNotificationConfig saved = configService.saveConfig(
                    shopId, enabled, timeoutMinutes, repeatSeconds, adminId);
            return R.ok("保存成功").put("data", configService.toConfigMap(saved));
        } catch (IllegalArgumentException e) {
            return R.error(400, e.getMessage());
        }
    }

    /**
     * 断线重连后按游标增量拉取未读实时通知。
     */
    @GetMapping({"/cashier/notifications/sync", "/api/v1/notifications/sync", "/user/notifications/sync"})
    public R syncNotifications(@RequestParam(name = "last_seq_id", required = false) Long lastSeqIdParam,
                               @RequestParam(name = "lastSeqId", required = false) Long lastSeqIdCamel,
                               @RequestParam(name = "limit", required = false) Integer limit,
                               @RequestParam(name = "shop_id", required = false) Integer shopIdParam,
                               @RequestParam(name = "shopId", required = false) Integer shopIdCamel,
                               @RequestParam(name = "client_type", required = false) String clientTypeParam,
                               @RequestParam(name = "clientType", required = false) String clientTypeCamel,
                               @RequestParam(name = "openid", required = false) String openid,
                               HttpServletRequest request) {
        UserOpenidResolution userRes = resolveAndVerifyCUserOpenid(request, openid);
        if (userRes.errorResponse != null) {
            return userRes.errorResponse;
        }
        String effectiveOpenid = userRes.effectiveOpenid;

        Integer shopId = resolveShopId(request, shopIdParam != null ? shopIdParam : shopIdCamel, null);
        Long lastSeqId = lastSeqIdParam != null ? lastSeqIdParam : (lastSeqIdCamel != null ? lastSeqIdCamel : 0L);
        String clientType = StringUtils.hasText(clientTypeParam)
                ? clientTypeParam
                : (StringUtils.hasText(clientTypeCamel)
                        ? clientTypeCamel
                        : (StringUtils.hasText(effectiveOpenid) || isUserPath(request)
                                ? UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM
                                : UnifiedSessionRegistry.CLIENT_TYPE_CASHIER));

        Map<String, Object> syncData = notificationService.syncNotifications(
                shopId, clientType, effectiveOpenid, lastSeqId, limit);
        return R.ok().put("data", syncData);
    }

    /**
     * 批量确认消息已读并向同店所有收银终端广播 ALERT_DISMISSED 消除告警。
     */
    @PostMapping({"/cashier/notifications/ack", "/api/v1/notifications/ack", "/user/notifications/ack"})
    public R acknowledgeNotifications(@RequestBody Map<String, Object> body,
                                      HttpServletRequest request) {
        if (body == null) {
            return R.error(400, "请求体不能为空");
        }
        String rawOpenid = body.get("openid") != null
                ? body.get("openid").toString().trim()
                : (body.get("openId") != null ? body.get("openId").toString().trim() : null);
        UserOpenidResolution userRes = resolveAndVerifyCUserOpenid(request, rawOpenid);
        if (userRes.errorResponse != null) {
            return userRes.errorResponse;
        }
        String effectiveOpenid = userRes.effectiveOpenid;

        Integer shopId = resolveShopId(request, null, body);
        List<String> messageIds = extractMessageIds(body);
        if (messageIds.isEmpty()) {
            return R.error(400, "message_ids 不能为空");
        }
        Integer adminId = resolveAdminId(request);
        String deviceId = request != null ? request.getHeader("X-Device-Id") : null;
        String ackedBy = StringUtils.hasText(deviceId)
                ? deviceId.trim()
                : (adminId != null
                        ? "admin:" + adminId
                        : (StringUtils.hasText(effectiveOpenid) ? "user:" + effectiveOpenid : "http_ack"));

        Integer ackShopId = (StringUtils.hasText(effectiveOpenid) && adminId == null) ? null : shopId;
        Map<String, Object> ackData = notificationService.acknowledgeNotifications(
                ackShopId, effectiveOpenid, messageIds, ackedBy);
        return R.ok("确认成功").put("data", ackData);
    }

    /**
     * 查询门店实时消息通道连接状态与待处理 P0 告警统计。
     */
    @GetMapping({"/admin/notifications/channel-stats", "/cashier/notifications/channel-stats"})
    public R getChannelStats(@RequestParam(name = "shop_id", required = false) Integer shopIdParam,
                             @RequestParam(name = "shopId", required = false) Integer shopIdCamel,
                             HttpServletRequest request) {
        Integer shopId = resolveShopId(request, shopIdParam != null ? shopIdParam : shopIdCamel, null);
        return R.ok().put("data", notificationService.getChannelStats(shopId));
    }

    /**
     * 触发联调测试实时推送。
     */
    @PostMapping({"/admin/notifications/test-push", "/cashier/notifications/test-push"})
    public R triggerTestPush(@RequestBody(required = false) Map<String, Object> body,
                             HttpServletRequest request) {
        Integer shopId = resolveShopId(request, null, body);
        String eventType = body != null && body.get("event_type") != null
                ? body.get("event_type").toString()
                : (body != null && body.get("eventType") != null ? body.get("eventType").toString() : "ORDER_PREP_TIMEOUT");
        Integer adminId = resolveAdminId(request);
        String operator = adminId != null ? "admin:" + adminId : "cashier_test";
        com.lanf.realtime.UnifiedMessageEnvelope env = notificationService.publishTestNotification(shopId, eventType, operator);
        return R.ok("测试推送已发送").put("data", env);
    }

    /**
     * 手动触发过期实时通知清理。
     */
    @PostMapping("/admin/notifications/cleanup")
    public R cleanupNotifications(@RequestBody(required = false) Map<String, Object> body) {
        Integer days = body != null ? parseIntOrNull(firstNonNull(body.get("retention_days"), body.get("retentionDays"))) : null;
        int deleted = notificationService.cleanupExpiredNotifications(days != null && days > 0 ? days : 7);
        Map<String, Object> res = new java.util.LinkedHashMap<>();
        res.put("deleted_count", deleted);
        return R.ok("清理完成").put("data", res);
    }

    /**
     * 解析并校验 C 端用户身份令牌（X-User-Token 或 UserIdentityInterceptor 注入属性），防止跨用户 openid 越权拉取或确认。
     */
    private UserOpenidResolution resolveAndVerifyCUserOpenid(HttpServletRequest request, String suppliedOpenid) {
        String cleanSupplied = StringUtils.hasText(suppliedOpenid) ? suppliedOpenid.trim() : null;
        if (request == null) {
            return UserOpenidResolution.ok(cleanSupplied);
        }

        Object attrOpenid = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
        if (attrOpenid instanceof String && StringUtils.hasText((String) attrOpenid)) {
            String verified = ((String) attrOpenid).trim();
            if (cleanSupplied != null && !verified.equals(cleanSupplied)) {
                return UserOpenidResolution.error(R.error(403, "用户身份与请求数据不一致"));
            }
            return UserOpenidResolution.ok(verified);
        }

        String userToken = request.getHeader("X-User-Token");
        if (StringUtils.hasText(userToken)) {
            if (jwtTokenService == null) {
                return UserOpenidResolution.error(R.error(401, "用户登录鉴权服务未就绪"));
            }
            try {
                Claims claims = jwtTokenService.parseToken(userToken.trim());
                if (claims == null || !"user".equals(claims.getSubject()) || !StringUtils.hasText(claims.getId())) {
                    return UserOpenidResolution.error(R.error(401, "用户登录已过期，请重新登录"));
                }
                String verified = claims.getId().trim();
                if (cleanSupplied != null && !verified.equals(cleanSupplied)) {
                    return UserOpenidResolution.error(R.error(403, "用户身份与请求数据不一致"));
                }
                return UserOpenidResolution.ok(verified);
            } catch (Exception e) {
                return UserOpenidResolution.error(R.error(401, "用户登录已过期，请重新登录"));
            }
        }

        return UserOpenidResolution.ok(cleanSupplied);
    }

    private static boolean isUserPath(HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return false;
        }
        return request.getRequestURI().startsWith("/user/");
    }

    private static class UserOpenidResolution {
        final String effectiveOpenid;
        final R errorResponse;

        private UserOpenidResolution(String effectiveOpenid, R errorResponse) {
            this.effectiveOpenid = effectiveOpenid;
            this.errorResponse = errorResponse;
        }

        static UserOpenidResolution ok(String openid) {
            return new UserOpenidResolution(openid, null);
        }

        static UserOpenidResolution error(R resp) {
            return new UserOpenidResolution(null, resp);
        }
    }

    private static Integer resolveShopId(HttpServletRequest request, Integer queryShopId, Map<String, Object> body) {
        if (request != null) {
            Object resolvedAttr = request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
            if (resolvedAttr instanceof Integer && (Integer) resolvedAttr > 0) {
                return (Integer) resolvedAttr;
            }
        }
        if (queryShopId != null && queryShopId > 0) {
            return queryShopId;
        }
        if (body != null) {
            Integer bodyShopId = parseIntOrNull(firstNonNull(body.get("shop_id"), body.get("shopId")));
            if (bodyShopId != null && bodyShopId > 0) {
                return bodyShopId;
            }
        }
        if (request != null) {
            Integer headerShopId = parseIntOrNull(request.getHeader("X-Shop-Id"));
            if (headerShopId != null && headerShopId > 0) {
                return headerShopId;
            }
        }
        return 1;
    }

    private static Integer resolveAdminId(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        Object attr = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (attr instanceof Integer) {
            return (Integer) attr;
        }
        return null;
    }

    private static List<String> extractMessageIds(Map<String, Object> body) {
        List<String> list = new ArrayList<>();
        Object single = firstNonNull(body.get("message_id"), body.get("messageId"));
        if (single != null && StringUtils.hasText(single.toString())) {
            list.add(single.toString().trim());
        }
        Object multi = firstNonNull(body.get("message_ids"), body.get("messageIds"));
        if (multi instanceof List<?>) {
            for (Object item : (List<?>) multi) {
                if (item != null && StringUtils.hasText(item.toString())) {
                    list.add(item.toString().trim());
                }
            }
        }
        return list;
    }

    private static Object firstNonNull(Object... items) {
        if (items == null) {
            return null;
        }
        for (Object item : items) {
            if (item != null) {
                return item;
            }
        }
        return null;
    }

    private static Integer parseIntOrNull(Object o) {
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o != null && StringUtils.hasText(o.toString())) {
            try {
                return Integer.parseInt(o.toString().trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }

    private static Boolean parseBooleanOrNull(Object o) {
        if (o instanceof Boolean) {
            return (Boolean) o;
        }
        if (o instanceof Number) {
            return ((Number) o).intValue() != 0;
        }
        if (o != null && StringUtils.hasText(o.toString())) {
            String s = o.toString().trim();
            if ("true".equalsIgnoreCase(s) || "1".equals(s)) {
                return Boolean.TRUE;
            }
            if ("false".equalsIgnoreCase(s) || "0".equals(s)) {
                return Boolean.FALSE;
            }
        }
        return null;
    }
}
