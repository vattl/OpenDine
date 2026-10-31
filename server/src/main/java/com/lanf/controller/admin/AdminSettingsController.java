package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.settings.service.ShopSettingsService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/**
 * 系统设置：导航概览、门店设置详情/保存、恢复总部继承。
 * 契约见《系统设置后端协调文档》§2；鉴权/门店上下文由 SysInterceptor 统一处理。
 */
@RestController
@RequestMapping("/admin/settings")
public class AdminSettingsController {

    @Autowired
    private ShopSettingsService shopSettingsService;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /** 设置导航概览：各模块权限、来源、摘要、告警数（不含支付敏感状态） */
    @GetMapping("/overview")
    public R overview() {
        int shopId = requireShopId();
        Integer adminId = currentAdminId();
        Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId(adminId);
        R r = new R();
        r.put("shopId", shopId);
        r.put("modules", shopSettingsService.overview(shopId, permissions));
        return r;
    }

    /** 门店设置详情：基础资料、营业时段、营业日、来源、版本 */
    @GetMapping("/store")
    public R getStore() {
        R r = new R();
        r.putAll(shopSettingsService.getStoreSetting(requireShopId()));
        return r;
    }

    /** 保存门店设置（门店覆盖）：字段 + version 乐观锁；冲突 409 + 最新版本摘要 */
    @PutMapping("/store")
    public R saveStore(@RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        Integer expectedVersion = toVersion(body.get("version"));
        Map<String, Object> result = shopSettingsService.saveStoreOverride(
                shopId, expectedVersion, body, currentAdminId());
        audit("save_store_override", "shop:" + shopId, result);
        R r = new R();
        r.putAll(result);
        return r;
    }

    /** 恢复总部继承：删除门店覆盖行，返回生效的总部配置（需 confirm=true + version） */
    @DeleteMapping("/store/override")
    public R deleteOverride(@RequestParam(defaultValue = "store") String module,
                            @RequestParam(required = false) Integer version,
                            @RequestParam(defaultValue = "false") boolean confirm) {
        int shopId = requireShopId();
        Map<String, Object> result = shopSettingsService.deleteOverride(
                shopId, module, version, confirm, currentAdminId());
        audit("restore_inheritance", "shop:" + shopId + ":" + module, result);
        R r = new R();
        r.putAll(result);
        return r;
    }

    // ---------------- 工具 ----------------

    private int requireShopId() {
        Object shopId = currentRequest.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        if (!(shopId instanceof Integer)) {
            throw new ApiException(4001, "SHOP_CONTEXT_MISSING", "缺少门店上下文，请传 X-Shop-Id");
        }
        return (Integer) shopId;
    }

    private Integer currentAdminId() {
        Object adminId = currentRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return adminId instanceof Integer ? (Integer) adminId : null;
    }

    private Integer toVersion(Object raw) {
        if (raw instanceof Number) {
            return ((Number) raw).intValue();
        }
        if (raw instanceof String && !((String) raw).trim().isEmpty()) {
            try {
                return Integer.parseInt(((String) raw).trim());
            } catch (NumberFormatException e) {
                throw new ApiException(400, "SETTINGS_VERSION_INVALID", "version 必须为整数");
            }
        }
        return null;
    }

    /** 写操作审计（失败不阻断业务） */
    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        try {
            securityAuditService.recordPrivilegedAction(currentRequest, requireShopId(),
                    "settings", action, targetId, currentAdminId(), snapshot, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
