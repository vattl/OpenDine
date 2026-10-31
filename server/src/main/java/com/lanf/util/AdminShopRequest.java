package com.lanf.util;

import com.lanf.interceptor.SysInterceptor;

import javax.servlet.http.HttpServletRequest;

/**
 * 运营端当前请求解析后的门店（由 {@link SysInterceptor} 写入，来自 X-Shop-Id / X-Shop-Code 等）。
 */
public final class AdminShopRequest {

    private AdminShopRequest() {
    }

    public static Integer getResolvedShopId(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        Object o = request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        return o instanceof Integer ? (Integer) o : null;
    }
}
