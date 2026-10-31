package com.lanf.kds.interceptor;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.util.KdsDeviceAuth;
import com.lanf.security.SecurityAuditService;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * 厨显端 /kds/** 设备令牌鉴权（免 JWT）与全链路链路追踪标识上下文初始化。
 */
@Component
public class KdsDeviceAuthInterceptor implements HandlerInterceptor {

    public static final String ATTR_KDS_DEVICE = "kdsDevice";
    public static final String ATTR_REQUEST_ID = "kds_request_id";
    public static final String ATTR_COMMAND_ID = "kds_command_id";
    public static final String ATTR_DEVICE_CODE = "kds_device_code";

    public static final String HEADER_REQUEST_ID = "X-Request-Id";
    public static final String HEADER_PROXY_REQUEST_ID = "X-KDS-Proxy-Request-Id";
    public static final String HEADER_COMMAND_ID = "X-KDS-Command-Id";
    public static final String HEADER_DEVICE_CODE = "X-KDS-Device-Code";
    private static final String HEADER_SHOP_ID = "X-Shop-Id";

    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired(required = false)
    private SecurityAuditService securityAuditService;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String path = request.getServletPath();
        if (path == null || path.isEmpty()) {
            path = request.getRequestURI();
        }
        if (path == null || (!path.startsWith("/kds/") && !path.startsWith("/api/v1/kds/"))) {
            return true;
        }

        // 1. 初始化链路追踪标识 (Trace correlation headers)
        String requestId = request.getHeader(HEADER_REQUEST_ID);
        if (requestId == null || requestId.trim().isEmpty()) {
            requestId = request.getHeader(HEADER_PROXY_REQUEST_ID);
        }
        if (requestId == null || requestId.trim().isEmpty()) {
            requestId = UUID.randomUUID().toString();
        } else {
            requestId = requestId.trim();
        }
        request.setAttribute(ATTR_REQUEST_ID, requestId);
        MDC.put("requestId", requestId);
        if (response != null) {
            response.setHeader(HEADER_REQUEST_ID, requestId);
        }

        String commandId = request.getHeader(HEADER_COMMAND_ID);
        if (commandId != null && !commandId.trim().isEmpty()) {
            commandId = commandId.trim();
            request.setAttribute(ATTR_COMMAND_ID, commandId);
            MDC.put("commandId", commandId);
        }

        String deviceCodeHeader = request.getHeader(HEADER_DEVICE_CODE);
        if (deviceCodeHeader != null && !deviceCodeHeader.trim().isEmpty()) {
            deviceCodeHeader = deviceCodeHeader.trim();
            request.setAttribute(ATTR_DEVICE_CODE, deviceCodeHeader);
            MDC.put("deviceCode", deviceCodeHeader);
        }

        // 2. 检查免鉴权登录端点
        if ("/kds/device/login".equals(path) || "/kds/device/login/".equals(path)
                || "/api/v1/kds/devices/login".equals(path) || "/api/v1/kds/devices/login/".equals(path)
                || "/api/v1/kds/device/login".equals(path) || "/api/v1/kds/device/login/".equals(path)) {
            return true;
        }

        // 3. 校验设备令牌（HTTP 强制 Header-only，退役 URL query token）
        String token = request.getHeader(KdsDeviceAuth.HEADER_DEVICE_TOKEN);
        if (token == null || token.trim().isEmpty()) {
            if (request.getParameter("device_token") != null) {
                auditDenied(request, null, "query_token_deprecated");
                writeJson(response, 401, "已废弃 URL 查询参数传递令牌，请在请求头携带 X-Kds-Device-Token");
                return false;
            }
            auditDenied(request, null, "missing_kds_device_token");
            writeJson(response, 401, "缺少厨显设备令牌 X-Kds-Device-Token");
            return false;
        }
        KdsDevice device = deviceService.findByToken(token.trim());
        if (device == null) {
            auditDenied(request, null, "invalid_kds_device_token");
            writeJson(response, 401, "设备未绑定或已禁用");
            return false;
        }

        if (device.getDevice_code() != null && !device.getDevice_code().trim().isEmpty()) {
            MDC.put("deviceCode", device.getDevice_code().trim());
        }

        String requestedShopId = request.getHeader(HEADER_SHOP_ID);
        if (requestedShopId != null && !requestedShopId.trim().isEmpty()) {
            final int parsedShopId;
            try {
                parsedShopId = Integer.parseInt(requestedShopId.trim());
            } catch (NumberFormatException invalidShopId) {
                auditDenied(request, device.getShop_id(), "invalid_kds_shop_context");
                writeJson(response, 403, "门店上下文无效");
                return false;
            }
            if (device.getShop_id() == null || device.getShop_id() != parsedShopId) {
                auditDenied(request, device.getShop_id(), "cross_shop_kds_device_token");
                writeJson(response, 403, "设备不属于当前门店");
                return false;
            }
        }
        request.setAttribute(ATTR_KDS_DEVICE, device);
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        MDC.remove("requestId");
        MDC.remove("commandId");
        MDC.remove("deviceCode");
    }

    private void auditDenied(HttpServletRequest request, Integer shopId, String reason) {
        if (securityAuditService != null) {
            securityAuditService.recordAccessDenied(request, null, shopId, 401, reason, "kds:device");
        }
    }

    private void writeJson(HttpServletResponse response, int code, String msg) throws Exception {
        response.setStatus(code == 401 ? 401 : code == 403 ? 403 : 400);
        response.setContentType("application/json;charset=UTF-8");
        Map<String, Object> body = new HashMap<>();
        body.put("code", code);
        body.put("msg", msg);
        response.getWriter().write(objectMapper.writeValueAsString(body));
    }
}
