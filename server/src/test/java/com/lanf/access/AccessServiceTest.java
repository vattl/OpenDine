package com.lanf.access;

import com.lanf.access.service.AccessService;
import com.lanf.access.service.AccessDecisionService;
import com.lanf.access.model.AccessDecision;
import com.lanf.common.ApiException;
import com.lanf.constant.AdminDataScope;
import com.lanf.entity.Admin;
import com.lanf.entity.AdminRole;
import com.lanf.entity.Permission;
import com.lanf.entity.Role;
import com.lanf.entity.RolePermission;
import com.lanf.mapper.AdminMapper;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.AdminShopMapper;
import com.lanf.mapper.PermissionMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.mapper.RolePermissionMapper;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 权限扩展单元测试：二次确认、角色被引用禁删、版本冲突、权限解释。
 */
class AccessServiceTest {

    private AccessService service;
    private AdminMapper adminMapper;
    private AdminRoleMapper adminRoleMapper;
    private AdminShopMapper adminShopMapper;
    private RoleMapper roleMapper;
    private PermissionMapper permissionMapper;
    private RolePermissionMapper rolePermissionMapper;
    private IAdminPermissionService adminPermissionService;
    private IAdminShopAccessService adminShopAccessService;
    private AccessDecisionService accessDecisionService;

    @BeforeEach
    void setUp() {
        adminMapper = mock(AdminMapper.class);
        adminRoleMapper = mock(AdminRoleMapper.class);
        adminShopMapper = mock(AdminShopMapper.class);
        roleMapper = mock(RoleMapper.class);
        permissionMapper = mock(PermissionMapper.class);
        rolePermissionMapper = mock(RolePermissionMapper.class);
        adminPermissionService = mock(IAdminPermissionService.class);
        adminShopAccessService = mock(IAdminShopAccessService.class);
        accessDecisionService = mock(AccessDecisionService.class);
        service = new AccessService();
        org.springframework.test.util.ReflectionTestUtils.setField(service, "adminMapper", adminMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "adminRoleMapper", adminRoleMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "adminShopMapper", adminShopMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "roleMapper", roleMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "permissionMapper", permissionMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "rolePermissionMapper", rolePermissionMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "adminPermissionService", adminPermissionService);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "adminShopAccessService", adminShopAccessService);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "accessDecisionService", accessDecisionService);
    }

    private Admin admin(int id) {
        Admin a = new Admin();
        a.setId(id);
        a.setUserName("staff" + id);
        return a;
    }

    private Role role(int id, String code, int sortOrder) {
        Role r = new Role();
        r.setId(id);
        r.setRole_code(code);
        r.setRole_name(code);
        r.setSort_order(sortOrder);
        r.setVersion(1);
        return r;
    }

    @Test
    void assignRequiresConfirm() {
        ApiException ex = assertThrows(ApiException.class,
                () -> service.assignEmployee(2, Collections.singletonList(3), null, false, 1));
        assertEquals(400, ex.getHttpStatus());
        assertEquals(AccessService.ERROR_CONFIRM_REQUIRED, ex.getErrorCode());
        verify(adminRoleMapper, never()).delete(any());
    }

    @Test
    void assignReplacesBindings() {
        when(adminMapper.selectById(2)).thenReturn(admin(2));
        when(roleMapper.selectBatchIds(any())).thenReturn(Collections.singletonList(role(3, "cashier", 10)));

        Map<String, Object> result = service.assignEmployee(2, Collections.singletonList(3),
                Arrays.asList(1, 2), true, 1);

        verify(adminRoleMapper).delete(any());
        verify(adminRoleMapper).insert(any(AdminRole.class));
        verify(adminShopMapper).delete(any());
        assertEquals(2, result.get("adminId"));
    }

    @Test
    void deleteRoleBlockedWhenReferencedByAdmin() {
        when(roleMapper.selectById(3)).thenReturn(role(3, "cashier", 10));
        when(adminRoleMapper.selectCount(any())).thenReturn(2);

        ApiException ex = assertThrows(ApiException.class, () -> service.deleteRole(3, true, 1));
        assertEquals(409, ex.getHttpStatus());
        assertEquals(AccessService.ERROR_ROLE_IN_USE, ex.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertEquals(2, data.get("adminCount"));
        verify(roleMapper, never()).deleteById(any());
    }

    @Test
    void deleteRoleSucceedsWhenUnreferenced() {
        when(roleMapper.selectById(3)).thenReturn(role(3, "cashier", 10));
        when(adminRoleMapper.selectCount(any())).thenReturn(0);

        service.deleteRole(3, true, 1);

        verify(rolePermissionMapper).delete(any());
        verify(roleMapper).deleteById(3);
    }

    @Test
    void updateRoleRejectsStaleVersion() {
        Role role = role(3, "cashier", 10);
        role.setVersion(2);
        when(roleMapper.selectById(3)).thenReturn(role);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("roleName", "新角色名");
        body.put("version", 1);
        ApiException ex = assertThrows(ApiException.class, () -> service.updateRole(3, body, 1));
        assertEquals(409, ex.getHttpStatus());
        assertEquals(AccessService.ERROR_ROLE_VERSION_CONFLICT, ex.getErrorCode());
    }

    @Test
    void updateRoleBumpsVersion() {
        Role role = role(3, "cashier", 10);
        role.setVersion(2);
        when(roleMapper.selectById(3)).thenReturn(role);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("roleName", "新角色名");
        body.put("version", 2);
        Map<String, Object> result = service.updateRole(3, body, 1);
        assertEquals(3, result.get("version"));
    }

    @Test
    void evaluateAllowsWithMatchedRole() {
        Map<String, Object> matchedRole = new LinkedHashMap<>();
        matchedRole.put("roleId", 3);
        AccessDecision decision = AccessDecision.allow("granted by matched roles");
        decision.setMatchedRoles(Collections.singletonList(matchedRole));
        when(accessDecisionService.evaluate(any())).thenReturn(decision);

        Map<String, Object> result = service.evaluate(2, 1, "order:view");

        assertTrue((Boolean) result.get("allow"));
        assertEquals("ALLOW", result.get("outcome"));
        List<?> matched = (List<?>) result.get("matchedRoles");
        assertEquals(1, matched.size());
    }

    @Test
    void evaluateDeniesWithoutGrant() {
        when(accessDecisionService.evaluate(any())).thenReturn(
                AccessDecision.deny("ACCESS_PERMISSION_DENIED", "no role grants this permission"));

        Map<String, Object> result = service.evaluate(2, null, "order:view");

        assertFalse((Boolean) result.get("allow"));
        assertEquals("DENY", result.get("outcome"));
        assertEquals("no role grants this permission", result.get("explanation"));
    }
}
