package com.lanf.security;

import com.lanf.entity.Admin;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.AdminPasswordUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class SensitiveOperationAuthorizationServiceTest {

    private IAdminService adminService;
    private IAdminPermissionService permissionService;
    private IAdminShopAccessService shopAccessService;
    private SensitiveOperationAuthorizationService service;

    @BeforeEach
    void setUp() {
        adminService = mock(IAdminService.class);
        permissionService = mock(IAdminPermissionService.class);
        shopAccessService = mock(IAdminShopAccessService.class);
        service = new SensitiveOperationAuthorizationService(
                adminService, permissionService, shopAccessService);
    }

    @Test
    void authorize_shouldFailClosedWhenCredentialsAreMissing() {
        SensitiveOperationAuthorizationService.Decision decision = service.authorize(
                Collections.emptyMap(), "order:operate:discount", 3, false);

        assertFalse(decision.isAllowed());
        assertEquals(401, decision.getCode());
        verifyNoInteractions(adminService, permissionService, shopAccessService);
    }

    @Test
    void authorize_shouldRejectWrongPasswordWithGenericMessage() {
        Admin manager = manager(22, "manager", "M1001", "correct-password");
        when(adminService.getOne(any())).thenReturn(manager);

        SensitiveOperationAuthorizationService.Decision decision = service.authorize(
                request("M1001", "wrong-password"), "order:operate:discount", 3, false);

        assertFalse(decision.isAllowed());
        assertEquals(401, decision.getCode());
        assertFalse(decision.getMessage().contains("wrong-password"));
        verifyNoInteractions(permissionService, shopAccessService);
    }

    @Test
    void authorize_shouldRejectMissingOperationPermission() {
        Admin manager = manager(22, "manager", "M1001", "correct-password");
        when(adminService.getOne(any())).thenReturn(manager);
        when(permissionService.getPermissionCodesByAdminId(22))
                .thenReturn(Collections.singleton("order:view"));

        SensitiveOperationAuthorizationService.Decision decision = service.authorize(
                request("M1001", "correct-password"), "order:operate:discount", 3, false);

        assertFalse(decision.isAllowed());
        assertEquals(403, decision.getCode());
        verify(shopAccessService, never()).listAccessibleShopIds(any());
    }

    @Test
    void authorize_shouldRejectEmployeeOutsideCurrentShop() {
        Admin manager = manager(22, "manager", "M1001", "correct-password");
        when(adminService.getOne(any())).thenReturn(manager);
        when(permissionService.getPermissionCodesByAdminId(22))
                .thenReturn(Collections.singleton("order:operate:refund"));
        when(shopAccessService.listAccessibleShopIds(22))
                .thenReturn(new HashSet<>(Arrays.asList(7, 8)));

        SensitiveOperationAuthorizationService.Decision decision = service.authorize(
                request("M1001", "correct-password"), "order:operate:refund", 3, false);

        assertFalse(decision.isAllowed());
        assertEquals(403, decision.getCode());
    }

    @Test
    void authorize_shouldAllowDifferentEmployeeWithPermissionAndShopScope() {
        Admin manager = manager(22, "manager", "M1001", "correct-password");
        when(adminService.getOne(any())).thenReturn(manager);
        when(permissionService.getPermissionCodesByAdminId(22))
                .thenReturn(Collections.singleton("order:operate:changePrice"));
        when(shopAccessService.listAccessibleShopIds(22))
                .thenReturn(Collections.singleton(3));

        SensitiveOperationAuthorizationService.Decision decision = service.authorize(
                request("M1001", "correct-password"), "order:operate:changePrice", 3, false);

        assertTrue(decision.isAllowed());
        assertEquals(Integer.valueOf(22), decision.getAdmin().getId());
    }

    @Test
    void authorize_shouldRequireExplicitSuperAdminForDelete() {
        Admin manager = manager(22, "manager", "M1001", "correct-password");
        when(adminService.getOne(any())).thenReturn(manager);
        when(permissionService.getPermissionCodesByAdminId(22))
                .thenReturn(Collections.singleton("order:delete"));
        when(shopAccessService.listAccessibleShopIds(22))
                .thenReturn(Collections.singleton(3));
        when(shopAccessService.isSuperAdmin(22)).thenReturn(false);

        SensitiveOperationAuthorizationService.Decision decision = service.authorize(
                request("M1001", "correct-password"), "order:delete", 3, true);

        assertFalse(decision.isAllowed());
        assertEquals(403, decision.getCode());
    }

    private static Admin manager(int id, String username, String workNo, String password) {
        Admin admin = new Admin();
        admin.setId(id);
        admin.setUserName(username);
        admin.setWorkNo(workNo);
        admin.setPassword(AdminPasswordUtil.encode(password));
        return admin;
    }

    private static Map<String, Object> request(String account, String password) {
        Map<String, Object> authorization = new HashMap<>();
        authorization.put("account", account);
        authorization.put("password", password);
        Map<String, Object> body = new HashMap<>();
        body.put("authorization", authorization);
        return body;
    }
}
