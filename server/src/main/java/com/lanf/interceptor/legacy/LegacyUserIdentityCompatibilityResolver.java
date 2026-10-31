package com.lanf.interceptor.legacy;

import com.lanf.config.properties.UserIdentityCompatibilityProperties;
import com.lanf.interceptor.UserIdentityInterceptor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.servlet.http.HttpServletRequest;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * 旧版小程序（未携带 X-User-Token）临时兼容鉴权解析器。
 * 包含精确方法+路径白名单、截止时间判定与上下文 openid 绑定。
 *
 * 【无痛回退设计】：
 * 1. 运行时关闭：设置 auth.c-user-identity.compatibility-enabled=false 即刻全部恢复 401 严格鉴权。
 * 2. 代码清理：删除本文件及 UserIdentityCompatibilityProperties，在 UserIdentityInterceptor 移除调用即可。
 */
@Component
public class LegacyUserIdentityCompatibilityResolver {

    private static final Logger log = LoggerFactory.getLogger(LegacyUserIdentityCompatibilityResolver.class);

    /**
     * 精确方法 + 路径白名单（严禁 /order/** 或 /coupon/** 通配放行）。
     */
    private static final Set<String> EXACT_LEGACY_WHITELIST = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            // 1. 订单核心接口
            "POST /order/create",
            "POST /order/addDishes",
            "POST /order/cancel",
            "GET /order/get",
            "POST /order/get",
            "GET /order/getOrder",
            "POST /order/getOrder",
            "POST /order/history",
            "POST /order/sendSubscribe",
            "POST /order/ai/chatSuggest",

            // 2. 用户资料接口
            "POST /order/getUserInfo",
            "POST /order/updateUser",
            "POST /order/updateAvatar",
            "POST /order/getOfficialPhoneNumber",

            // 3. 支付与充值
            "POST /order/getPrepayId",
            "POST /order/payByBalance",
            "POST /order/recharge",
            "POST /order/rechargeHistory",

            // 4. 优惠券接口
            "POST /coupon/getAvailable",
            "POST /coupon/getUserAvailableCoupons",
            "POST /coupon/getUserCoupons",
            "POST /coupon/receive",
            "GET /coupon/redeem",

            // 5. 邀请活动接口
            "POST /invite/getCode",
            "POST /invite/getRecords",
            "POST /invite/getReward",

            // 6. 排队接口
            "POST /queue/ticket/create",
            "GET /queue/ticket/status",
            "POST /queue/ticket/cancel",

            // 7. 外卖与收货地址接口（仅限常规外卖与微信支付）
            "GET /order/takeout/address/list",
            "POST /order/takeout/address/save",
            "POST /order/takeout/address/delete",
            "POST /order/takeout/address/setDefault",
            "POST /order/takeout/preview",
            "POST /order/takeout/create",
            "POST /order/takeout/order/list",
            "GET /order/takeout/order/detail",
            "GET /order/takeout/order/tracking"
    )));

    @Autowired(required = false)
    private UserIdentityCompatibilityProperties properties;
    @Autowired(required = false)
    private org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    public LegacyUserIdentityCompatibilityResolver() {
    }

    public LegacyUserIdentityCompatibilityResolver(UserIdentityCompatibilityProperties properties) {
        this.properties = properties;
    }

    public LegacyUserIdentityCompatibilityResolver(UserIdentityCompatibilityProperties properties,
                                                   org.springframework.jdbc.core.JdbcTemplate jdbcTemplate) {
        this.properties = properties;
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 尝试通过旧版兼容逻辑校验请求并注入 authenticatedUserOpenid。
     *
     * @param request 当前 HTTP 请求
     * @param normalizedPath 规范化后的请求路径
     * @param suppliedOpenids 请求中提取到的所有 openid
     * @return true 若命中兼容白名单并成功放行；false 否则转入 401
     */
    public boolean tryResolveAndBind(HttpServletRequest request, String normalizedPath, Set<String> suppliedOpenids) {
        if (properties == null || !properties.isEffective()) {
            return false;
        }

        String method = request.getMethod() != null ? request.getMethod().toUpperCase(Locale.ROOT) : "GET";
        String routeKey = method + " " + normalizedPath;

        if (!EXACT_LEGACY_WHITELIST.contains(routeKey)) {
            return false;
        }

        // 1. 优先从请求参数或请求体提取 openid
        String resolvedOpenid = null;
        if (suppliedOpenids != null && !suppliedOpenids.isEmpty()) {
            if (suppliedOpenids.size() > 1) {
                log.warn("旧版兼容鉴权拒绝：请求携带了多个冲突的 openid, count={}, path={}", suppliedOpenids.size(), normalizedPath);
                return false;
            }
            resolvedOpenid = suppliedOpenids.iterator().next();
        }

        // 2. 若旧版未显式传 openid（如订单详情 /order/getOrder 仅传 order_no，或 /order/get 仅传桌台号），从数据库受控资源反查归属
        if ((resolvedOpenid == null || resolvedOpenid.trim().isEmpty()) && jdbcTemplate != null) {
            resolvedOpenid = resolveOpenidFromResource(request, normalizedPath);
        }

        if (resolvedOpenid != null && !resolvedOpenid.trim().isEmpty()) {
            request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, resolvedOpenid.trim());
        }

        log.info("event=legacy_c_auth_used method={} path={} openid={} ip={}",
                method, normalizedPath, maskOpenid(resolvedOpenid), getClientIp(request));
        return true;
    }

    private String resolveOpenidFromResource(HttpServletRequest request, String normalizedPath) {
        try {
            if ("/order/getOrder".equals(normalizedPath)) {
                String orderNo = extractParam(request, "order_no", "orderNo");
                if (orderNo != null && !orderNo.trim().isEmpty()) {
                    List<String> openids = jdbcTemplate.query(
                            "SELECT openid FROM t_order WHERE order_no = ? ORDER BY id DESC LIMIT 1",
                            (rs, rowNum) -> rs.getString("openid"),
                            orderNo.trim()
                    );
                    return (openids != null && !openids.isEmpty()) ? openids.get(0) : null;
                }
            } else if ("/order/get".equals(normalizedPath)) {
                String tableNumber = extractParam(request, "table_number", "tableNumber");
                String transacStatus = extractParam(request, "transac_status", "transacStatus");
                if (tableNumber != null && !tableNumber.trim().isEmpty()) {
                    String status = (transacStatus != null && !transacStatus.trim().isEmpty()) ? transacStatus.trim() : "unsettled";
                    List<String> openids = jdbcTemplate.query(
                            "SELECT openid FROM t_order WHERE table_number = ? AND transac_status = ? ORDER BY id DESC LIMIT 1",
                            (rs, rowNum) -> rs.getString("openid"),
                            tableNumber.trim(), status
                    );
                    return (openids != null && !openids.isEmpty()) ? openids.get(0) : null;
                }
            } else if ("/queue/ticket/status".equals(normalizedPath) || "/queue/ticket/cancel".equals(normalizedPath)) {
                String ticketNo = extractParam(request, "ticketNo", "ticket_no");
                if (ticketNo != null && !ticketNo.trim().isEmpty()) {
                    List<String> openids = jdbcTemplate.query(
                            "SELECT openid FROM t_queue_ticket WHERE ticket_no = ? ORDER BY id DESC LIMIT 1",
                            (rs, rowNum) -> rs.getString("openid"),
                            ticketNo.trim()
                    );
                    return (openids != null && !openids.isEmpty()) ? openids.get(0) : null;
                }
            } else if ("/order/takeout/order/detail".equals(normalizedPath) || "/order/takeout/order/tracking".equals(normalizedPath)) {
                String orderNo = extractParam(request, "order_no", "orderNo");
                if (orderNo != null && !orderNo.trim().isEmpty()) {
                    List<String> openids = jdbcTemplate.query(
                            "SELECT openid FROM t_order WHERE order_no = ? ORDER BY id DESC LIMIT 1",
                            (rs, rowNum) -> rs.getString("openid"),
                            orderNo.trim()
                    );
                    return (openids != null && !openids.isEmpty()) ? openids.get(0) : null;
                }
            } else if ("/order/takeout/address/delete".equals(normalizedPath) || "/order/takeout/address/setDefault".equals(normalizedPath)) {
                String addressId = extractParam(request, "id", "address_id", "addressId");
                if (addressId != null && !addressId.trim().isEmpty()) {
                    List<String> openids = jdbcTemplate.query(
                            "SELECT openid FROM t_user_address WHERE id = ? ORDER BY id DESC LIMIT 1",
                            (rs, rowNum) -> rs.getString("openid"),
                            addressId.trim()
                    );
                    return (openids != null && !openids.isEmpty()) ? openids.get(0) : null;
                }
            }
        } catch (Exception e) {
            log.warn("反查旧版请求资源归属异常: path={}, err={}", normalizedPath, e.getMessage());
        }
        return null;
    }

    private String extractParam(HttpServletRequest request, String... paramNames) {
        if (request == null || paramNames == null) {
            return null;
        }
        for (String name : paramNames) {
            String val = request.getParameter(name);
            if (val != null && !val.trim().isEmpty()) {
                return val.trim();
            }
        }
        if (request instanceof com.lanf.filter.CachedBodyHttpServletRequest) {
            try {
                com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
                Map<?, ?> body = mapper.readValue(request.getInputStream(), Map.class);
                if (body != null) {
                    for (String name : paramNames) {
                        Object val = body.get(name);
                        if (val != null && !val.toString().trim().isEmpty()) {
                            return val.toString().trim();
                        }
                    }
                }
            } catch (Exception ignored) {
            }
        }
        return null;
    }

    private static String maskOpenid(String openid) {
        if (openid == null || openid.length() <= 8) {
            return "***";
        }
        return openid.substring(0, 4) + "..." + openid.substring(openid.length() - 4);
    }

    private static String getClientIp(HttpServletRequest request) {
        String xff = request.getHeader("X-Forwarded-For");
        if (xff != null && !xff.trim().isEmpty()) {
            int idx = xff.indexOf(',');
            return idx > 0 ? xff.substring(0, idx).trim() : xff.trim();
        }
        return request.getRemoteAddr();
    }
}
