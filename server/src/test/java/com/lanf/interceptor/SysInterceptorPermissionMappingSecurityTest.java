package com.lanf.interceptor;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.DbApiPermissionMapping;
import com.lanf.constant.AdminDataScope;
import com.lanf.entity.Admin;
import com.lanf.filter.CachedBodyHttpServletRequest;
import com.lanf.security.JwtTokenService;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.IAdminService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.method.HandlerMethod;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SysInterceptorPermissionMappingSecurityTest {

    private static final JwtTokenService TOKEN_SERVICE = new JwtTokenService(
            "test-current-secret-must-have-at-least-32-bytes", "");

    @Test
    void unknownAdminEndpointIsDeniedWhenNoPermissionMappingExists() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        SecurityAuditService auditService = mock(SecurityAuditService.class);
        ReflectionTestUtils.setField(interceptor, "securityAuditService", auditService);
        MockHttpServletRequest request = adminRequest("POST", "/admin/config/unmapped-danger");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());

        assertFalse(allowed, "未登记权限的后台接口必须失败关闭");
        assertEquals(403, responseBody(response).get("code"));
        verify(auditService).recordAccessDenied(eq(request), eq(7), isNull(), eq(403),
                eq("permission_mapping_missing"), isNull());
    }

    @Test
    void builtInInventoryCannotAuthorizeWhenDatabaseMappingIsMissing() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings(Collections.singleton("cashier:operate"));
        SecurityAuditService auditService = mock(SecurityAuditService.class);
        ReflectionTestUtils.setField(interceptor, "securityAuditService", auditService);
        MockHttpServletRequest request = adminRequest("POST", "/cashier/order/updatePrice");
        request.addHeader("X-Shop-Id", "7");
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(403, responseBody(response).get("code"));
        verify(auditService).recordAccessDenied(eq(request), eq(7), isNull(), eq(403),
                eq("permission_mapping_missing"), isNull());
    }

    @Test
    void authenticatedBootstrapEndpointRemainsAvailableWithoutBusinessPermission() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        MockHttpServletRequest request = adminRequest("GET", "/admin/me/permissions");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());

        assertTrue(allowed, "登录管理员必须能读取自己的权限，用于前端初始化");
        assertEquals(7, request.getAttribute(SysInterceptor.ATTR_ADMIN_ID));
    }

    @Test
    void apiAdminCashierCompatibilityRouteCannotBypassPermissionCheck() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        MockHttpServletRequest request = adminRequest("GET", "/api/admin/cashier/kds/bootstrap");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());

        assertFalse(allowed, "/api/admin/cashier/** 兼容路由必须执行管理员权限校验");
        assertEquals(403, responseBody(response).get("code"));
    }

    @Test
    void feieyunRouteIsInterceptedAndRequiresAuthentication() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/feieyun/print");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());

        assertFalse(allowed, "/api/feieyun/** 路由必须执行管理员/收银员鉴权拦截");
        assertEquals(401, responseBody(response).get("code"));
    }

    @Test
    void tokenIsRejectedAfterAdminTokenVersionChanges() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        IAdminService adminService = mock(IAdminService.class);
        Admin current = new Admin();
        current.setId(7);
        current.setTokenVersion(2);
        when(adminService.getById(7)).thenReturn(current);
        ReflectionTestUtils.setField(interceptor, "adminService", adminService);

        MockHttpServletRequest request = adminRequest("GET", "/admin/me/permissions", 1);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(401, responseBody(response).get("code"));
    }

    @Test
    void legacyOrderManagementRouteCannotUsePublicOrderWhitelist() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        MockHttpServletRequest request = adminRequest("POST", "/order/ChangeBusiness");
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(403, responseBody(response).get("code"));
    }

    @Test
    void legacyActivityWriteCannotUsePublicActivityWhitelist() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings();
        MockHttpServletRequest request = adminRequest("POST", "/activity/deletePopup");
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(403, responseBody(response).get("code"));
    }

    @Test
    void invoiceWorkbenchEndpointsDoNotRequireShopContext() throws Exception {
        SysInterceptor interceptor = interceptorWithoutDbMappings(Collections.singleton("order:view"));
        DbApiPermissionMapping dbMapping = mock(DbApiPermissionMapping.class);
        when(dbMapping.getRequiredPermission("GET", "/admin/order/invoice/list")).thenReturn("order:view");
        ReflectionTestUtils.setField(interceptor, "dbApiPermissionMapping", dbMapping);

        MockHttpServletRequest request = adminRequest("GET", "/admin/order/invoice/list");
        // 显式不携带 X-Shop-Id 门店头
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());
        assertTrue(allowed, "财务开票工作台列表接口在未传 X-Shop-Id 时必须被放行以支持全店汇总");
        assertEquals(7, request.getAttribute(SysInterceptor.ATTR_ADMIN_ID));
    }

    @Test
    void camelCaseBodyShopIdCannotOverrideAuthenticatedShopHeader() throws Exception {
        SysInterceptor interceptor = interceptorWithRequiredPermission(
                "order:config", false, Collections.singleton("order:config"));
        MockHttpServletRequest raw = adminRequest("PUT", "/admin/config/zsq-auto-api");
        raw.addHeader("X-Shop-Id", "7");
        raw.setContentType("application/json");
        raw.setContent("{\"shopId\":8}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(4001, responseBody(response).get("code"));
    }

    @Test
    void superAdminIsExemptedFromMissingPermissionCode() throws Exception {
        // 双保险：超级管理员即使角色权限表漏配某权限码，也拥有全部权限（docs/权限设计.md §5 步骤5）
        SysInterceptor interceptor = interceptorWithRequiredPermission(
                "order:operate:changePrice", true, Collections.emptySet());
        MockHttpServletRequest request = adminRequest("POST", "/cashier/order/updatePrice");
        request.addHeader("X-Shop-Id", "7");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());

        assertTrue(allowed, "super_admin 角色必须豁免缺失的权限码");
        assertEquals(7, request.getAttribute(SysInterceptor.ATTR_ADMIN_ID));
    }

    @Test
    void nonSuperAdminIsDeniedForMissingPermissionCode() throws Exception {
        // 对照：非超管缺权限码仍必须 403，豁免不得放宽普通员工
        SysInterceptor interceptor = interceptorWithRequiredPermission(
                "order:operate:changePrice", false, Collections.emptySet());
        SecurityAuditService auditService = mock(SecurityAuditService.class);
        ReflectionTestUtils.setField(interceptor, "securityAuditService", auditService);
        MockHttpServletRequest request = adminRequest("POST", "/cashier/order/updatePrice");
        request.addHeader("X-Shop-Id", "7");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, handler());

        assertFalse(allowed, "非超管缺少权限码时必须 403");
        assertEquals(403, responseBody(response).get("code"));
        assertEquals("无权限：order:operate:changePrice", responseBody(response).get("msg"));
        verify(auditService).recordAccessDenied(eq(request), eq(7), isNull(), eq(403),
                eq("permission_denied"), eq("order:operate:changePrice"));
    }

    private static SysInterceptor interceptorWithoutDbMappings() {
        return interceptorWithoutDbMappings(Collections.emptySet());
    }

    /** 构造带指定 required 权限码的拦截器：superAdmin=true 时 resolveScope 为 HQ（跳过门店集合校验）。 */
    private static SysInterceptor interceptorWithRequiredPermission(String requiredCode,
                                                                    boolean superAdmin,
                                                                    java.util.Set<String> permissions) {
        SysInterceptor interceptor = new SysInterceptor();
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        when(permissionService.getPermissionCodesByAdminId(7)).thenReturn(permissions);
        DbApiPermissionMapping dbMapping = mock(DbApiPermissionMapping.class);
        when(dbMapping.getRequiredPermission(anyString(), anyString())).thenReturn(requiredCode);
        ReflectionTestUtils.setField(interceptor, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(interceptor, "dbApiPermissionMapping", dbMapping);
        ReflectionTestUtils.setField(interceptor, "shopService", mock(IShopService.class));
        IAdminService adminService = mock(IAdminService.class);
        Admin current = new Admin();
        current.setId(7);
        current.setTokenVersion(0);
        when(adminService.getById(7)).thenReturn(current);
        ReflectionTestUtils.setField(interceptor, "adminService", adminService);
        ReflectionTestUtils.setField(interceptor, "jwtTokenService", TOKEN_SERVICE);
        IAdminShopAccessService shopAccess = mock(IAdminShopAccessService.class);
        when(shopAccess.isSuperAdmin(7)).thenReturn(superAdmin);
        when(shopAccess.resolveScope(7)).thenReturn(superAdmin ? AdminDataScope.HQ : AdminDataScope.SHOP);
        when(shopAccess.listAccessibleShopIds(7)).thenReturn(Collections.singleton(7));
        ReflectionTestUtils.setField(interceptor, "adminShopAccessService", shopAccess);
        ReflectionTestUtils.setField(interceptor, "securityAuditService", mock(SecurityAuditService.class));
        return interceptor;
    }

    private static SysInterceptor interceptorWithoutDbMappings(java.util.Set<String> permissions) {
        SysInterceptor interceptor = new SysInterceptor();
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        when(permissionService.getPermissionCodesByAdminId(7)).thenReturn(permissions);
        DbApiPermissionMapping dbMapping = mock(DbApiPermissionMapping.class);
        when(dbMapping.getRequiredPermission(anyString(), anyString())).thenReturn(null);
        ReflectionTestUtils.setField(interceptor, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(interceptor, "dbApiPermissionMapping", dbMapping);
        ReflectionTestUtils.setField(interceptor, "shopService", mock(IShopService.class));
        IAdminService adminService = mock(IAdminService.class);
        Admin current = new Admin();
        current.setId(7);
        current.setTokenVersion(0);
        when(adminService.getById(7)).thenReturn(current);
        ReflectionTestUtils.setField(interceptor, "adminService", adminService);
        ReflectionTestUtils.setField(interceptor, "jwtTokenService", TOKEN_SERVICE);
        IAdminShopAccessService shopAccess = mock(IAdminShopAccessService.class);
        when(shopAccess.resolveScope(7)).thenReturn(AdminDataScope.SHOP);
        when(shopAccess.listAccessibleShopIds(7)).thenReturn(Collections.singleton(7));
        ReflectionTestUtils.setField(interceptor, "adminShopAccessService", shopAccess);
        ReflectionTestUtils.setField(interceptor, "securityAuditService", mock(SecurityAuditService.class));
        return interceptor;
    }

    private static MockHttpServletRequest adminRequest(String method, String path) {
        return adminRequest(method, path, 0);
    }

    private static MockHttpServletRequest adminRequest(String method, String path, int tokenVersion) {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setRequestURI(path);
        Map<String, Object> claims = new HashMap<>();
        claims.put("tokenVersion", tokenVersion);
        request.addHeader("Authorization", "Bearer "
                + TOKEN_SERVICE.createToken("7", "admin", 60_000, claims));
        return request;
    }

    private static HandlerMethod handler() throws NoSuchMethodException {
        return new HandlerMethod(new TestController(), TestController.class.getDeclaredMethod("handle"));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> responseBody(MockHttpServletResponse response) throws Exception {
        return new ObjectMapper().readValue(response.getContentAsString(), Map.class);
    }

    private static final class TestController {
        public void handle() {
        }
    }
}
