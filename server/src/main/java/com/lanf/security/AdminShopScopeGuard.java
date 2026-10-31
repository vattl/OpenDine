package com.lanf.security;

import com.lanf.constant.AdminDataScope;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.servlet.http.HttpServletRequest;
import java.util.Set;

/** Defense-in-depth guard for shop/global selectors used by admin controllers. */
@Component
public class AdminShopScopeGuard {

    private final HttpServletRequest request;
    private final IAdminShopAccessService accessService;
    @Autowired(required = false)
    private SecurityAuditService securityAuditService;

    @Autowired
    public AdminShopScopeGuard(HttpServletRequest request, IAdminShopAccessService accessService) {
        this.request = request;
        this.accessService = accessService;
    }

    /** Success returns null and writes the authorized target (0 means global) into holder[0]. */
    public R resolveTargetShopId(Integer requestedShopId, int[] holder) {
        if (holder == null || holder.length == 0) {
            throw new IllegalArgumentException("target holder is required");
        }
        Integer adminId = currentAdminId();
        if (adminId == null) {
            return deny(401, "未登录或登录已过期", "missing_admin_identity", requestedShopId);
        }
        AdminDataScope scope;
        try {
            scope = accessService.resolveScope(adminId);
        } catch (RuntimeException e) {
            return deny(4003, "管理员数据范围校验失败", "shop_scope_resolution_failed", requestedShopId);
        }
        Integer contextShopId = AdminShopRequest.getResolvedShopId(request);

        if (requestedShopId == null) {
            if (contextShopId != null && contextShopId > 0) {
                holder[0] = contextShopId;
                return null;
            }
            if (scope == AdminDataScope.HQ) {
                holder[0] = 0;
                return null;
            }
            return deny(4003, "非总部账号必须指定授权门店", "missing_authorized_shop", null);
        }
        if (requestedShopId <= 0) {
            if (scope != AdminDataScope.HQ) {
                return deny(4003, "仅总部账号可访问全局配置", "global_scope_denied", requestedShopId);
            }
            holder[0] = 0;
            return null;
        }
        if (contextShopId != null && contextShopId > 0 && !requestedShopId.equals(contextShopId)) {
            return deny(4003, "参数 shopId 与当前门店上下文不一致", "shop_context_mismatch", requestedShopId);
        }
        if (scope != AdminDataScope.HQ) {
            Set<Integer> allowed = accessService.listAccessibleShopIds(adminId);
            if (allowed == null || !allowed.contains(requestedShopId)) {
                return deny(4003, "门店不在当前管理员可操作范围内", "shop_scope_denied", requestedShopId);
            }
        }
        holder[0] = requestedShopId;
        return null;
    }

    public R requireHeadquarters() {
        Integer adminId = currentAdminId();
        if (adminId == null) {
            return deny(401, "未登录或登录已过期", "missing_admin_identity", null);
        }
        try {
            return accessService.resolveScope(adminId) == AdminDataScope.HQ
                    ? null : deny(4003, "该操作仅限总部管理员", "headquarters_scope_required", null);
        } catch (RuntimeException e) {
            return deny(4003, "管理员数据范围校验失败", "shop_scope_resolution_failed", null);
        }
    }

    private R deny(int code, String message, String reason, Integer requestedShopId) {
        if (securityAuditService != null) {
            securityAuditService.recordAccessDenied(
                    request, currentAdminId(), requestedShopId, code, reason, null);
        }
        return R.error(code, message);
    }

    private Integer currentAdminId() {
        Object value = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return value instanceof Integer ? (Integer) value : null;
    }
}
