package com.lanf.interceptor;

import com.lanf.config.DbApiPermissionMapping;
import com.lanf.constant.AdminDataScope;
import com.lanf.filter.CachedBodyHttpServletRequest;
import com.lanf.entity.Admin;
import com.lanf.security.JwtTokenService;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.IAdminService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopChainSupport;
import com.lanf.util.SafeLogValue;
import com.lanf.util.StringUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * B 端鉴权拦截器，严格按 docs/权限设计.md 第 5 节「鉴权流程（B 端）」实现：
 * 1. 请求头 Authorization: Bearer &lt;JWT&gt;（或 Authorization: &lt;JWT&gt;，去掉 Bearer 前缀）
 * 2. 校验 JWT 有效且 subject 为管理员；未登录或非法 token → 401
 * 3. 从 JWT 的 id 解析管理员 ID，按 t_admin_role → t_role_permission → t_permission 得到权限集合
 * 4. 按请求路径+方法查 t_api_permission（由 DbApiPermissionMapping 提供）得到所需权限码
 * 5. 拥有该权限码则放行，否则 403
 */
@Component
public class SysInterceptor implements HandlerInterceptor {

    /** 请求属性：当前管理员 ID（仅 /admin 且鉴权通过后设置） */
    public static final String ATTR_ADMIN_ID = "adminId";
    /** 请求属性：链路追踪 ID（用于排查 401/403） */
    public static final String ATTR_TRACE_ID = "traceId";
    /** 请求属性：当前请求解析出的门店 ID */
    public static final String ATTR_RESOLVED_SHOP_ID = "resolvedShopId";
    /** 请求属性：当前管理员可访问门店 ID 集合（请求级缓存） */
    public static final String ATTR_ALLOWED_SHOP_IDS = "allowedShopIds";

    private static final Logger log = LoggerFactory.getLogger(SysInterceptor.class);
    private static final String SUBJECT_ADMIN = "admin";

    /** 只要求有效管理员身份、不要求业务权限码的最小入口集合。 */
    private static final List<String> AUTHENTICATED_ONLY_PATHS = Arrays.asList(
            "/admin/me/permissions",
            "/admin/me/shops",
            "/admin/app/version",
            "/admin/push/device/register",
            "/admin/push/device/unregister",
            "/admin/push/preference",
            "/admin/rbac/api-permissions/reload"
    );

    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private DbApiPermissionMapping dbApiPermissionMapping;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private IAdminService adminService;
    @Autowired
    private JwtTokenService jwtTokenService;
    @Autowired
    private SecurityAuditService securityAuditService;

    /**
     * 连锁：以下 /admin 路径不要求「当前门店」上下文（登录后选店前、全局配置、RBAC、门店主数据维护等）。
     * 其余 /admin/** 与全部 /cashier/** 必须带 X-Shop-Id 或 X-Shop-Code（或与 body/query 一致），避免跨店读数。
     */
    private static final List<String> ADMIN_SHOP_CONTEXT_EXEMPT_PREFIXES = Arrays.asList(
            "/admin/me/",
            "/admin/modifyPassword",
            "/admin/shop/list",
            "/admin/shop/save",
            "/admin/rbac/",
            "/admin/administrator/",
            "/admin/access/",
            "/admin/config/",
            "/admin/log/",
            "/admin/app/",
            "/admin/push/device/unregister",
            "/admin/unit/",
            "/admin/order/auto-accept",
            "/admin/order/invoice/",
            // 微信订阅消息全局模板与日志审计：全店通用
            "/admin/subscribe/",
            // 公告：总部可不传门店创建「全店」公告；门店账号仍须在请求头带当前店
            "/admin/announcement/"
    );

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String path = request.getRequestURI();
        String traceId = resolveTraceId(request);
        request.setAttribute(ATTR_TRACE_ID, traceId);
        if (!(handler instanceof HandlerMethod)) {
            return true;
        }

        // ---------- 步骤 1：读取请求头 Authorization: Bearer <JWT> 或 Authorization: <JWT> ----------
        String authHeader = request.getHeader("Authorization");
        if (StringUtil.isEmpty(authHeader)) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=missing_authorization", traceId, path, request.getMethod());
            auditDenied(request, null, null, 401, "missing_authorization", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }
        String token = authHeader.trim();
        if (token.startsWith("Bearer ")) {
            token = token.substring(7).trim();
        }
        if (token.isEmpty()) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=empty_token", traceId, path, request.getMethod());
            auditDenied(request, null, null, 401, "empty_token", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }

        // ---------- 步骤 2：校验 JWT 有效且 subject 为管理员身份；未登录或非法 token → 401 ----------
        Claims claims;
        try {
            claims = jwtTokenService.parseToken(token);
        } catch (Exception e) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=jwt_exception, messageSummary={}",
                    traceId, path, request.getMethod(), SafeLogValue.summarize(e.getMessage()));
            auditDenied(request, null, null, 401, "invalid_token", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }
        if (claims == null) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=null_claims", traceId, path, request.getMethod());
            auditDenied(request, null, null, 401, "null_claims", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }

        // /admin 与 /cashier 均需管理员身份并设置 adminId
        boolean isAdminPath = "/admin".equals(path) || path.startsWith("/admin/")
                || isLegacyAdminPath(request.getMethod(), path);
        boolean isCashierPath = path.startsWith("/cashier")
                || path.startsWith("/api/admin/cashier/")
                || path.startsWith("/api/pos/")
                || path.startsWith("/api/feieyun/")
                || isOfflineCollectionCashierPath(path);
        if (!isAdminPath && !isCashierPath) {
            return true;
        }

        if (!SUBJECT_ADMIN.equals(claims.getSubject())) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=invalid_subject, subject={}",
                    traceId, path, request.getMethod(), claims.getSubject());
            auditDenied(request, null, null, 401, "invalid_subject", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }
        String adminIdStr = claims.getId();
        if (StringUtil.isEmpty(adminIdStr)) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=empty_admin_id", traceId, path, request.getMethod());
            auditDenied(request, null, null, 401, "empty_admin_id", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }
        Integer adminId;
        try {
            adminId = Integer.parseInt(adminIdStr);
        } catch (NumberFormatException e) {
            log.warn("鉴权失败: traceId={}, path={}, method={}, reason=invalid_admin_id, adminIdStr={}",
                    traceId, path, request.getMethod(), adminIdStr);
            auditDenied(request, null, null, 401, "invalid_admin_id", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }

        Admin currentAdmin = adminService.getById(adminId);
        Integer claimTokenVersion = claims.get("tokenVersion", Integer.class);
        int currentTokenVersion = currentAdmin == null || currentAdmin.getTokenVersion() == null
                ? 0 : currentAdmin.getTokenVersion();
        if (currentAdmin == null || claimTokenVersion == null || claimTokenVersion != currentTokenVersion) {
            log.warn("鉴权失败: traceId={}, adminId={}, path={}, method={}, reason=revoked_token",
                    traceId, adminId, path, request.getMethod());
            auditDenied(request, adminId, null, 401, "revoked_token", null);
            writeReplicationAwareJson(response, path, 401, "未登录或登录已过期");
            return false;
        }

        // ---------- 步骤 2.1：账号生命周期状态校验 (ACTIVE, DISABLED, LOCKED, RESIGNED) ----------
        String accountStatus = currentAdmin.getAccountStatus() != null ? currentAdmin.getAccountStatus() : Admin.STATUS_ACTIVE;
        if (Admin.STATUS_DISABLED.equals(accountStatus)) {
            log.warn("账号停用拒绝: traceId={}, adminId={}, path={}", traceId, adminId, path);
            auditDenied(request, adminId, null, 403, "account_disabled", null);
            writeReplicationAwareJson(response, path, 403, "ACCESS_ACCOUNT_DISABLED: 账号已被停用");
            return false;
        }
        if (Admin.STATUS_RESIGNED.equals(accountStatus)) {
            log.warn("员工离职拒绝: traceId={}, adminId={}, path={}", traceId, adminId, path);
            auditDenied(request, adminId, null, 403, "account_resigned", null);
            writeReplicationAwareJson(response, path, 403, "ACCESS_ACCOUNT_RESIGNED: 员工已离职");
            return false;
        }
        if (Admin.STATUS_LOCKED.equals(accountStatus)
                && currentAdmin.getLockedUntil() != null && currentAdmin.getLockedUntil().after(new java.util.Date())) {
            log.warn("账号锁定拒绝: traceId={}, adminId={}, path={}", traceId, adminId, path);
            auditDenied(request, adminId, null, 423, "account_locked", null);
            writeReplicationAwareJson(response, path, 423, "ACCESS_ACCOUNT_LOCKED: 账号已被锁定");
            return false;
        }

        // ---------- 步骤 2.2：强制下线时间戳校验 ----------
        if (currentAdmin.getForceLogoutAt() != null && claims.getIssuedAt() != null) {
            if (claims.getIssuedAt().before(currentAdmin.getForceLogoutAt())) {
                log.warn("会话强制下线拒绝: traceId={}, adminId={}, iat={}, forceLogoutAt={}",
                        traceId, adminId, claims.getIssuedAt(), currentAdmin.getForceLogoutAt());
                auditDenied(request, adminId, null, 401, "session_revoked", null);
                writeReplicationAwareJson(response, path, 401, "ACCESS_SESSION_REVOKED: 会话已被强制下线，请重新登录");
                return false;
            }
        }

        // ---------- 步骤 2.3：权限版本校验 (permission_version 即时失效) ----------
        Long claimPermVer = claims.get("permissionVersion") != null
                ? ((Number) claims.get("permissionVersion")).longValue() : null;
        long currentPermVer = currentAdmin.getPermissionVersion() != null
                ? currentAdmin.getPermissionVersion() : 1L;
        if (claimPermVer != null && claimPermVer != currentPermVer) {
            log.warn("权限版本不一致拒绝: traceId={}, adminId={}, claimVer={}, dbVer={}",
                    traceId, adminId, claimPermVer, currentPermVer);
            auditDenied(request, adminId, null, 403, "permission_changed", null);
            writeReplicationAwareJson(response, path, 403, "ACCESS_PERMISSION_CHANGED: 员工权限已变更，请刷新");
            return false;
        }

        // ---------- 步骤 3：从 JWT 的 id 得管理员 ID，按 t_admin_role → t_role_permission → t_permission 得权限集合 ----------
        Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId(adminId);

        // ---------- 步骤 4：根据请求路径+方法查接口-权限映射，得所需权限码 ----------
        String required = dbApiPermissionMapping.getRequiredPermission(request.getMethod(), path);

        if (required == null && !isAuthenticatedOnlyPath(path)) {
            log.error("权限映射缺失，拒绝请求: traceId={}, adminId={}, path={}, method={}",
                    traceId, adminId, path, request.getMethod());
            auditDenied(request, adminId, null, 403, "permission_mapping_missing", null);
            writeReplicationAwareJson(response, path, 403, "接口权限未配置");
            return false;
        }

        // ---------- 步骤 5：拥有该权限码则放行，否则 403 ----------
        // super_admin 角色拥有全部权限（docs/权限设计.md §5 步骤5）：作为双保险，
        // 即使角色权限表漏配某新增权限码，超管也不会被误伤；非超管仍严格按表校验。
        if (required != null && !hasRequiredPermission(permissions, required)) {
            if (adminShopAccessService.isSuperAdmin(adminId)) {
                log.info("超级管理员权限豁免: traceId={}, adminId={}, path={}, method={}, required={}",
                        traceId, adminId, path, request.getMethod(), required);
            } else {
                log.warn("权限不足: traceId={}, adminId={}, path={}, method={}, required={}",
                        traceId, adminId, path, request.getMethod(), required);
                auditDenied(request, adminId, null, 403, "permission_denied", required);
                writeReplicationAwareJson(response, path, 403, "无权限：" + required);
                return false;
            }
        }

        // ---------- 步骤 6：门店范围校验（P2，4001/4003；连锁：运营/收银默认必带门店） ----------
        String method = request.getMethod();
        boolean shopRequired = requiresShopContext(method, path);
        Integer resolvedShopId;
        try {
            resolvedShopId = resolveShopId(request);
        } catch (RuntimeException e) {
            log.warn("门店上下文解析失败: traceId={}, adminId={}, path={}, method={}, messageSummary={}",
                    traceId, adminId, path, method, SafeLogValue.summarize(e.getMessage()));
            auditDenied(request, adminId, null, 4001, "invalid_shop_context", required);
            writeReplicationAwareJson(response, path, 4001, e.getMessage());
            return false;
        }
        if (shopRequired && resolvedShopId == null) {
            log.warn("门店上下文缺失: traceId={}, adminId={}, path={}, method={}", traceId, adminId, path, method);
            auditDenied(request, adminId, null, 4001, "missing_shop_context", required);
            writeReplicationAwareJson(response, path, 4001, "缺少门店上下文，请传 X-Shop-Id 或 X-Shop-Code");
            return false;
        }
        if (resolvedShopId != null) {
            AdminDataScope scope = adminShopAccessService.resolveScope(adminId);
            if (scope != AdminDataScope.HQ) {
                Set<Integer> allowedShopIds = adminShopAccessService.listAccessibleShopIds(adminId);
                request.setAttribute(ATTR_ALLOWED_SHOP_IDS, allowedShopIds);
                if (allowedShopIds == null || !allowedShopIds.contains(resolvedShopId)) {
                    log.warn("门店越权: traceId={}, adminId={}, path={}, method={}, resolvedShopId={}",
                            traceId, adminId, path, method, resolvedShopId);
                    auditDenied(request, adminId, resolvedShopId, 4003, "shop_scope_denied", required);
                    writeReplicationAwareJson(response, path, 4003, "门店不在当前管理员可操作范围内");
                    return false;
                }
            }
            request.setAttribute(ATTR_RESOLVED_SHOP_ID, resolvedShopId);
        }

        request.setAttribute(ATTR_ADMIN_ID, adminId);
        if (required != null) {
            log.info("鉴权通过: traceId={}, adminId={}, path={}, method={}, required={}",
                    traceId, adminId, path, request.getMethod(), required);
        }
        return true;
    }

    private void auditDenied(HttpServletRequest request, Integer adminId, Integer shopId,
                             int resultCode, String reason, String requiredPermission) {
        if (securityAuditService != null) {
            securityAuditService.recordAccessDenied(
                    request, adminId, shopId, resultCode, reason, requiredPermission);
        }
    }

    private String resolveTraceId(HttpServletRequest request) {
        String traceId = request.getHeader("X-Trace-Id");
        if (!StringUtil.isEmpty(traceId)) {
            return traceId.trim();
        }
        return UUID.randomUUID().toString().replace("-", "");
    }

    private Integer resolveShopId(HttpServletRequest request) {
        Integer bodyOrQueryShopId = ShopChainSupport.parseBodyShopId(request.getParameter("shop_id"));
        if (bodyOrQueryShopId == null) {
            bodyOrQueryShopId = ShopChainSupport.parseBodyShopId(request.getParameter("shopId"));
        }
        String bodyOrQueryShopCode = ShopChainSupport.parseBodyShopCode(request.getParameter("shop_code"));
        if (bodyOrQueryShopId == null && StringUtil.isEmpty(bodyOrQueryShopCode)) {
            Map<String, Object> jsonBody = parseJsonBody(request);
            if (jsonBody != null && !jsonBody.isEmpty()) {
                bodyOrQueryShopId = ShopChainSupport.parseBodyShopId(jsonBody.get("shop_id"));
                if (bodyOrQueryShopId == null) {
                    bodyOrQueryShopId = ShopChainSupport.parseBodyShopId(jsonBody.get("shopId"));
                }
                bodyOrQueryShopCode = ShopChainSupport.parseBodyShopCode(jsonBody.get("shop_code"));
                if (StringUtil.isEmpty(bodyOrQueryShopCode)) {
                    bodyOrQueryShopCode = ShopChainSupport.parseBodyShopCode(jsonBody.get("shopCode"));
                }
            }
        }
        return ShopChainSupport.resolveShopChain(request, bodyOrQueryShopId, bodyOrQueryShopCode,
                shopService::requireActiveShopIdByCode);
    }

    /**
     * 需要解析出门店 ID 的请求：全部 {@code /cashier/**}；{@code /admin/**} 除 {@link #ADMIN_SHOP_CONTEXT_EXEMPT_PREFIXES} 外。
     */
    private boolean requiresShopContext(String method, String path) {
        if (path == null) {
            return false;
        }
        if (path.startsWith("/cashier/")
                || path.startsWith("/api/admin/cashier/")
                || isOfflineCollectionCashierPath(path)) {
            return true;
        }
        if (path.startsWith("/admin/")) {
            return !isAdminShopContextExempt(path);
        }
        return false;
    }

    /**
     * A mapping may use {@code |} for a small, explicit set of alternative
     * permissions. This is used only for shared read-only catalog endpoints.
     */
    public static boolean hasRequiredPermission(Set<String> permissions, String required) {
        if (permissions == null || permissions.isEmpty() || required == null || required.trim().isEmpty()) {
            return false;
        }
        for (String candidate : required.split("[|]")) {
            if (permissions.contains(candidate.trim())) {
                return true;
            }
        }
        return false;
    }

    private static boolean isOfflineCollectionCashierPath(String path) {
        String normalized = path != null && path.endsWith("/")
                ? path.substring(0, path.length() - 1)
                : path;
        return "/pay/offline-collect/temp-qrcode".equals(normalized)
                || "/pay/offline-collect/confirm".equals(normalized)
                || "/pay/offline-collect/cancel".equals(normalized);
    }

    private static boolean isLegacyAdminPath(String method, String path) {
        if ("POST".equalsIgnoreCase(method)) {
            return "/order/ChangeBusiness".equals(path)
                    || "/order/ChangeIsReview".equals(path)
                    || "/order/notice".equals(path)
                    || "/order/autoAcceptAndPrint".equals(path)
                    || "/activity/updatePopup".equals(path)
                    || "/activity/addPopup".equals(path)
                    || "/activity/deletePopup".equals(path);
        }
        if ("GET".equalsIgnoreCase(method)) {
            return "/order/printContent".equals(path)
                    || "/activity/getAllPopup".equals(path);
        }
        return "DELETE".equalsIgnoreCase(method) && path.startsWith("/order/delete/");
    }

    private static boolean isAdminShopContextExempt(String path) {
        for (String p : ADMIN_SHOP_CONTEXT_EXEMPT_PREFIXES) {
            if (path.startsWith(p)) {
                return true;
            }
        }
        return false;
    }

    private static boolean isAuthenticatedOnlyPath(String path) {
        String normalized = path != null && path.endsWith("/")
                ? path.substring(0, path.length() - 1)
                : path;
        return AUTHENTICATED_ONLY_PATHS.contains(normalized);
    }

    private Map<String, Object> parseJsonBody(HttpServletRequest request) {
        if (!(request instanceof CachedBodyHttpServletRequest)) {
            return Collections.emptyMap();
        }
        String contentType = request.getContentType();
        if (contentType == null || !contentType.toLowerCase().contains("application/json")) {
            return Collections.emptyMap();
        }
        try {
            return new ObjectMapper().readValue(request.getInputStream(), Map.class);
        } catch (Exception ignore) {
            return Collections.emptyMap();
        }
    }

    /** 按权限设计 5.1：401/403 响应 body 为 { "code": 401|403, "msg": "..." } */
    private void writeJson(HttpServletResponse response, int code, String msg) throws Exception {
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType("application/json;charset=UTF-8");
        response.setCharacterEncoding("UTF-8");
        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("code", code);
        body.put("msg", msg);
        response.getWriter().write(new ObjectMapper().writeValueAsString(body));
    }

    private void writeReplicationAwareJson(HttpServletResponse response, String path, int legacyCode, String msg)
            throws Exception {
        if (path == null || !path.startsWith("/admin/kds/replication/")) {
            writeJson(response, legacyCode, msg);
            return;
        }
        int httpStatus = legacyCode == 401 ? 401 : (legacyCode == 403 || legacyCode == 4003 ? 403 : 400);
        int businessCode = httpStatus == 400 ? 4000 : 4010;
        response.setStatus(httpStatus);
        response.setContentType("application/json;charset=UTF-8");
        response.setCharacterEncoding("UTF-8");
        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("code", businessCode);
        body.put("msg", msg);
        response.getWriter().write(new ObjectMapper().writeValueAsString(body));
    }
}
