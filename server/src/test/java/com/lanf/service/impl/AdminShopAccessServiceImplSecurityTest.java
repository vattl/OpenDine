package com.lanf.service.impl;

import com.lanf.entity.AdminRole;
import com.lanf.entity.Role;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.AdminRegionMapper;
import com.lanf.mapper.AdminShopMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

class AdminShopAccessServiceImplSecurityTest {

    @Test
    void adminWithoutRolesIsNotHeadquartersAdmin() {
        AdminRoleMapper adminRoleMapper = mock(AdminRoleMapper.class);
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.emptyList());

        AdminShopAccessServiceImpl service = new AdminShopAccessServiceImpl();
        ReflectionTestUtils.setField(service, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(service, "roleMapper", mock(RoleMapper.class));

        assertFalse(service.isSuperAdmin(7),
                "未绑定角色不能成为超级管理员");
        assertFalse(service.isHeadquartersAdmin(7),
                "未绑定角色不能获得总部数据范围");
    }

    @Test
    void explicitSuperAdminRoleHasHeadquartersScope() {
        AdminRoleMapper adminRoleMapper = mock(AdminRoleMapper.class);
        RoleMapper roleMapper = mock(RoleMapper.class);
        AdminRole link = new AdminRole();
        link.setRole_id(3);
        Role role = new Role();
        role.setRole_code("super_admin");
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.singletonList(link));
        when(roleMapper.selectById(3)).thenReturn(role);

        AdminShopAccessServiceImpl service = new AdminShopAccessServiceImpl();
        ReflectionTestUtils.setField(service, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(service, "roleMapper", roleMapper);

        assertTrue(service.isSuperAdmin(7));
        assertTrue(service.isHeadquartersAdmin(7));
    }

    @Test
    void roleLookupFailureDoesNotGrantSuperAdmin() {
        AdminRoleMapper adminRoleMapper = mock(AdminRoleMapper.class);
        when(adminRoleMapper.selectList(any())).thenThrow(new RuntimeException("database unavailable"));

        AdminShopAccessServiceImpl service = new AdminShopAccessServiceImpl();
        ReflectionTestUtils.setField(service, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(service, "roleMapper", mock(RoleMapper.class));

        assertFalse(service.isSuperAdmin(7),
                "角色查询异常时必须失败关闭，不能授予超级管理员权限");
    }

    @Test
    void shopRoleWithoutExplicitScopeCannotInheritTheOnlyActiveShop() {
        AdminRoleMapper adminRoleMapper = mock(AdminRoleMapper.class);
        RoleMapper roleMapper = mock(RoleMapper.class);
        AdminRegionMapper adminRegionMapper = mock(AdminRegionMapper.class);
        AdminShopMapper adminShopMapper = mock(AdminShopMapper.class);
        IShopService shopService = mock(IShopService.class);
        AdminRole link = new AdminRole();
        link.setRole_id(2);
        Role role = new Role();
        role.setRole_code("store_manager");
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.singletonList(link));
        when(roleMapper.selectById(2)).thenReturn(role);
        when(adminRegionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminShopMapper.selectList(any())).thenReturn(Collections.emptyList());

        AdminShopAccessServiceImpl service = new AdminShopAccessServiceImpl();
        ReflectionTestUtils.setField(service, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(service, "roleMapper", roleMapper);
        ReflectionTestUtils.setField(service, "adminRegionMapper", adminRegionMapper);
        ReflectionTestUtils.setField(service, "adminShopMapper", adminShopMapper);
        ReflectionTestUtils.setField(service, "shopService", shopService);

        assertTrue(service.listAccessibleShops(7).isEmpty());
        verify(shopService, never()).list(any());
    }
}
