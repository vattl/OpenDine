package com.lanf.interceptor;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.filter.CachedBodyHttpServletRequest;
import com.lanf.security.JwtTokenService;
import com.lanf.security.SecurityAuditService;
import io.jsonwebtoken.Claims;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.Collection;

/** Enforces server-issued C-side identity tokens on user-owned data and writes. */
@Component
public class UserIdentityInterceptor implements HandlerInterceptor {

    public static final String ATTR_USER_OPENID = "authenticatedUserOpenid";
    private static final String SUBJECT_USER = "user";
    private static final String LEGACY_PHONE_BINDING_PATH = "/order/getOfficialPhoneNumber";
    private static final Logger log = LoggerFactory.getLogger(UserIdentityInterceptor.class);

    private static final Set<String> PUBLIC_PATHS = new HashSet<>(Arrays.asList(
            "/order/calculateFinishTime",
            "/order/Business",
            "/order/table_verify",
            "/order/table_status",
            "/order/banners",
            "/order/getOpenid",
            "/order/pay/notify",
            "/order/refund/notify",
            "/order/ai/tools",
            "/order/takeout/config",
            "/coupon/getTemplate",
            "/queue/config",
            "/invite/poster",
            "/invite/poster/alt"
    ));

    private static final Set<String> ADMIN_MANAGED_PATHS = new HashSet<>(Arrays.asList(
            "/order/ChangeBusiness",
            "/order/ChangeIsReview",
            "/order/notice",
            "/order/printContent",
            "/order/autoAcceptAndPrint"
    ));

    @Autowired
    private JwtTokenService jwtTokenService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired(required = false)
    private com.lanf.interceptor.legacy.LegacyUserIdentityCompatibilityResolver legacyCompatibilityResolver;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        if (!(handler instanceof HandlerMethod)) {
            return true;
        }
        String path = normalize(request.getRequestURI());
        if (ADMIN_MANAGED_PATHS.contains(path) || path.startsWith("/order/delete/")) {
            return true;
        }
        Set<String> suppliedOpenids = resolveSuppliedOpenids(request);
        if (isPublicPath(path) && suppliedOpenids.isEmpty()) {
            return true;
        }

        String token = request.getHeader("X-User-Token");
        if (token != null && !token.trim().isEmpty()) {
            String authenticatedOpenid;
            try {
                Claims claims = jwtTokenService.parseToken(token.trim());
                if (!SUBJECT_USER.equals(claims.getSubject()) || claims.getId() == null || claims.getId().trim().isEmpty()) {
                    throw new IllegalArgumentException("invalid user token subject");
                }
                authenticatedOpenid = claims.getId().trim();
            } catch (RuntimeException e) {
                deny(response, 401, "用户登录已过期，请重新登录");
                log.warn("C端鉴权失败: path={}, method={}, reason=invalid_user_token", path, request.getMethod());
                auditDenied(request, 401, "invalid_user_token");
                return false;
            }

            for (String suppliedOpenid : suppliedOpenids) {
                if (!authenticatedOpenid.equals(suppliedOpenid)) {
                    deny(response, 403, "用户身份与请求数据不一致");
                    log.warn("C端越权拒绝: path={}, method={}, reason=openid_mismatch", path, request.getMethod());
                    auditDenied(request, 403, "openid_mismatch");
                    return false;
                }
            }
            request.setAttribute(ATTR_USER_OPENID, authenticatedOpenid);
            return true;
        }

        // 临时兼容旧版小程序（无 X-User-Token），后续废弃时仅需移除此段调用
        if (legacyCompatibilityResolver != null && legacyCompatibilityResolver.tryResolveAndBind(request, path, suppliedOpenids)) {
            return true;
        }

        deny(response, 401, "用户登录已过期，请重新登录");
        log.warn("C端鉴权失败: path={}, method={}, reason=missing_user_token", path, request.getMethod());
        auditDenied(request, 401, "missing_user_token");
        return false;
    }

    private void auditDenied(HttpServletRequest request, int resultCode, String reason) {
        if (securityAuditService != null) {
            securityAuditService.recordAccessDenied(request, null, null, resultCode, reason, "user:owned-resource");
        }
    }

    private boolean isPublicPath(String path) {
        return PUBLIC_PATHS.contains(path);
    }

    private Set<String> resolveSuppliedOpenids(HttpServletRequest request) {
        Set<String> values = new HashSet<>();
        String queryOpenid = trimToNull(request.getParameter("openid"));
        if (queryOpenid == null) {
            queryOpenid = trimToNull(request.getParameter("openId"));
        }
        if (queryOpenid != null) {
            values.add(queryOpenid);
        }
        if (!(request instanceof CachedBodyHttpServletRequest)) {
            return values;
        }
        try {
            Map<String, Object> body = new ObjectMapper().readValue(request.getInputStream(),
                    new TypeReference<Map<String, Object>>() { });
            collectOpenids(body, values);
        } catch (Exception e) {
            // Malformed JSON is rejected by MVC; identity enforcement remains token-based.
        }
        return values;
    }

    private void collectOpenids(Object value, Set<String> output) {
        if (value instanceof Map) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
                String key = String.valueOf(entry.getKey());
                if ("openid".equals(key) || "openId".equals(key)) {
                    String openid = entry.getValue() == null ? null : trimToNull(entry.getValue().toString());
                    if (openid != null) {
                        output.add(openid);
                    }
                } else {
                    collectOpenids(entry.getValue(), output);
                }
            }
        } else if (value instanceof Collection) {
            for (Object item : (Collection<?>) value) {
                collectOpenids(item, output);
            }
        }
    }

    private static String normalize(String path) {
        if (path != null && path.length() > 1 && path.endsWith("/")) {
            return path.substring(0, path.length() - 1);
        }
        return path == null ? "" : path;
    }

    private static String trimToNull(String value) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        return value.trim();
    }

    private static void deny(HttpServletResponse response, int code, String message) throws Exception {
        response.setStatus(code);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write("{\"code\":" + code + ",\"msg\":\"" + message + "\"}");
    }
}
