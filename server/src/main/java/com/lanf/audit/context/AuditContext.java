package com.lanf.audit.context;

import com.lanf.interceptor.SysInterceptor;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.servlet.http.HttpServletRequest;

/**
 * 从当前请求上下文解析审计所需信息，复用 {@link SysInterceptor} 写入的 request 属性
 * （adminId / resolvedShopId / traceId），保证与既有越权审计同口径。
 */
public final class AuditContext {

    private AuditContext() {
    }

    public static HttpServletRequest currentRequest() {
        ServletRequestAttributes attrs =
                (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        return attrs != null ? attrs.getRequest() : null;
    }

    public static Integer currentAdminId(HttpServletRequest request) {
        Object v = request != null ? request.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        if (v instanceof Integer) {
            return (Integer) v;
        }
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        return null;
    }

    public static Integer currentShopId(HttpServletRequest request) {
        Object v = request != null ? request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID) : null;
        if (v instanceof Integer) {
            return (Integer) v;
        }
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        return null;
    }

    public static String currentTraceId(HttpServletRequest request) {
        Object v = request != null ? request.getAttribute(SysInterceptor.ATTR_TRACE_ID) : null;
        return v != null ? v.toString() : null;
    }

    public static String clientIp(HttpServletRequest request) {
        return request != null ? request.getRemoteAddr() : null;
    }
}
