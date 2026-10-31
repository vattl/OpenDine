package com.lanf.inventory.web;

import com.lanf.common.ApiException;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.IAdminPermissionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;
import java.util.Set;

/**
 * 库存扩展 Web 支撑：门店上下文、管理员上下文、inventory:manage 判定（结算字段过滤用）、写操作审计。
 * 鉴权由 SysInterceptor + t_api_permission 统一处理，此处仅做字段级权限与防御。
 */
@Component
public class InventoryWebSupport {

    private static final Logger log = LoggerFactory.getLogger(InventoryWebSupport.class);

    public static final String PERM_INVENTORY_MANAGE = "inventory:manage";

    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private SecurityAuditService securityAuditService;

    /** 当前门店（/admin/** 拦截器已解析；取不到时防御 4001） */
    public int requireShopId(HttpServletRequest request) {
        Object shopId = request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        if (!(shopId instanceof Integer)) {
            throw new ApiException(4001, "SHOP_CONTEXT_MISSING", "缺少门店上下文，请传 X-Shop-Id");
        }
        return (Integer) shopId;
    }

    public Integer currentAdminId(HttpServletRequest request) {
        Object adminId = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return adminId instanceof Integer ? (Integer) adminId : null;
    }

    /** 是否持有 inventory:manage；供应商结算字段等敏感信息仅此权限可见 */
    public boolean canManage(Integer adminId) {
        if (adminId == null) {
            return false;
        }
        try {
            Set<String> codes = adminPermissionService.getPermissionCodesByAdminId(adminId);
            return codes != null && codes.contains(PERM_INVENTORY_MANAGE);
        } catch (Exception e) {
            log.warn("[inventory] permission lookup failed: {}", e.getMessage());
            return false;
        }
    }

    /** 写操作审计（失败不阻断业务，见规范 §3） */
    public void audit(HttpServletRequest request, int shopId, String action, String targetId,
                      Map<String, Object> snapshot, Integer adminId) {
        try {
            securityAuditService.recordPrivilegedAction(request, shopId, "inventory",
                    action, targetId, adminId, snapshot, null);
        } catch (Exception e) {
            log.warn("[inventory] audit failed (ignored): {}", e.getMessage());
        }
    }
}
