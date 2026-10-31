package com.lanf.kds.interceptor;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Fail-closed retirement boundary for legacy KDS mutations.
 *
 * <p>Cloud-authority KDS mutations must pass through the V2 command ledger.
 * Device login and heartbeat remain lifecycle operations rather than business
 * mutations, so they are deliberately preserved.</p>
 */
@Component
public class KdsLegacyWriteRetirementInterceptor implements HandlerInterceptor {

    private static final String KDS_PREFIX = "/kds/";
    private static final String KDS_V1_PREFIX = "/api/v1/kds/";
    private static final String KDS_V2_PREFIX = "/kds/v2/";
    private static final String RETIRED_MESSAGE =
            "旧版 KDS 写接口已停用，请升级并使用 /kds/v2/commands";

    private final ObjectMapper objectMapper;

    public KdsLegacyWriteRetirementInterceptor(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws Exception {
        String path = normalizedPath(request);
        if (!isKdsPath(path) || !isWriteMethod(request.getMethod())) {
            return true;
        }
        if (path.startsWith(KDS_V2_PREFIX) || isDeviceLifecyclePath(path)) {
            return true;
        }

        response.setStatus(HttpServletResponse.SC_GONE);
        response.setCharacterEncoding("UTF-8");
        response.setContentType("application/json;charset=UTF-8");
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Deprecation", "true");
        response.setHeader("Link", "</kds/v2/commands>; rel=\"successor-version\"");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", HttpServletResponse.SC_GONE);
        body.put("msg", RETIRED_MESSAGE);
        response.getWriter().write(objectMapper.writeValueAsString(body));
        return false;
    }

    private String normalizedPath(HttpServletRequest request) {
        String path = request.getServletPath();
        if (path == null || path.trim().isEmpty()) {
            path = request.getRequestURI();
        }
        if (path == null || path.isEmpty()) {
            return "";
        }
        while (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        return path;
    }

    private boolean isKdsPath(String path) {
        return path.startsWith(KDS_PREFIX) || path.startsWith(KDS_V1_PREFIX);
    }

    private boolean isWriteMethod(String method) {
        String normalized = method == null ? "" : method.toUpperCase(Locale.ROOT);
        return "POST".equals(normalized)
                || "PUT".equals(normalized)
                || "PATCH".equals(normalized)
                || "DELETE".equals(normalized);
    }

    private boolean isDeviceLifecyclePath(String path) {
        return "/kds/device/login".equals(path)
                || "/kds/device/heartbeat".equals(path)
                || "/api/v1/kds/device/login".equals(path)
                || "/api/v1/kds/device/heartbeat".equals(path)
                || "/api/v1/kds/devices/login".equals(path)
                || "/api/v1/kds/devices/heartbeat".equals(path);
    }
}
