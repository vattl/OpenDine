package com.lanf.service.impl;

import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.RolePermissionMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AdminPermissionServiceImplSecurityTest {

    @Test
    void adminWithoutRolesHasNoPermissions() {
        AdminRoleMapper adminRoleMapper = mock(AdminRoleMapper.class);
        RolePermissionMapper rolePermissionMapper = mock(RolePermissionMapper.class);
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.emptyList());

        AdminPermissionServiceImpl service = service(adminRoleMapper, rolePermissionMapper);

        Set<String> result = service.getPermissionCodesByAdminId(7);

        assertTrue(result.isEmpty(), "未绑定角色的管理员必须没有权限，不能隐式成为超级管理员");
    }

    @Test
    void permissionQueryFailureFailsClosed() {
        AdminRoleMapper adminRoleMapper = mock(AdminRoleMapper.class);
        when(adminRoleMapper.selectList(any())).thenThrow(new RuntimeException("database unavailable"));

        AdminPermissionServiceImpl service = service(
                adminRoleMapper, mock(RolePermissionMapper.class));

        Set<String> result = service.getPermissionCodesByAdminId(7);

        assertTrue(result.isEmpty(), "权限数据异常时必须拒绝授权");
    }

    private static AdminPermissionServiceImpl service(AdminRoleMapper adminRoleMapper,
                                                       RolePermissionMapper rolePermissionMapper) {
        AdminPermissionServiceImpl service = new AdminPermissionServiceImpl();
        ReflectionTestUtils.setField(service, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(service, "rolePermissionMapper", rolePermissionMapper);
        return service;
    }
}
