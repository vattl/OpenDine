package com.lanf.access.service;

import com.lanf.common.ApiException;
import com.lanf.entity.Admin;
import com.lanf.mapper.AdminMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 员工状态变更链路审计：PUT /admin/access/employees/{adminId}/status → AccessService.updateEmployeeStatus。
 * 验证「返回成功但 DB 状态不变」是否存在代码层根因（写入未执行/字段未设置/分支未命中）。
 */
class AccessServiceEmployeeStatusTest {

    private AccessService service;
    private AdminMapper adminMapper;

    @BeforeEach
    void setUp() {
        service = new AccessService();
        adminMapper = mock(AdminMapper.class);
        ReflectionTestUtils.setField(service, "adminMapper", adminMapper);
    }

    private static Admin admin(int id, String accountStatus) {
        Admin a = new Admin();
        a.setId(id);
        a.setUserName("user" + id);
        a.setAccountStatus(accountStatus);
        a.setPermissionVersion(3L);
        a.setTokenVersion(1);
        return a;
    }

    @Test
    void disableEmployeeWritesAllFieldsAndReturnsNewStatus() {
        when(adminMapper.selectById(5)).thenReturn(admin(5, Admin.STATUS_ACTIVE));
        when(adminMapper.updateById(org.mockito.ArgumentMatchers.any(Admin.class))).thenReturn(1);

        Map<String, Object> result = service.updateEmployeeStatus(5, Admin.STATUS_DISABLED, 999);

        assertEquals(Admin.STATUS_DISABLED, result.get("accountStatus"));
        ArgumentCaptor<Admin> captor = ArgumentCaptor.forClass(Admin.class);
        verify(adminMapper).updateById(captor.capture());
        Admin updated = captor.getValue();
        assertEquals(Admin.STATUS_DISABLED, updated.getAccountStatus());
        assertEquals(4L, updated.getPermissionVersion().longValue());
        assertNotNull(updated.getForceLogoutAt(), "停用必须刷新 force_logout_at");
        assertEquals(2, updated.getTokenVersion().intValue(), "停用必须递增 token_version");
    }

    @Test
    void reactivateEmployeeKeepsForceLogoutAndTokenVersion() {
        when(adminMapper.selectById(5)).thenReturn(admin(5, Admin.STATUS_DISABLED));
        when(adminMapper.updateById(org.mockito.ArgumentMatchers.any(Admin.class))).thenReturn(1);

        service.updateEmployeeStatus(5, Admin.STATUS_ACTIVE, 999);

        ArgumentCaptor<Admin> captor = ArgumentCaptor.forClass(Admin.class);
        verify(adminMapper).updateById(captor.capture());
        Admin updated = captor.getValue();
        assertEquals(Admin.STATUS_ACTIVE, updated.getAccountStatus());
        assertEquals(4L, updated.getPermissionVersion().longValue());
        assertNull(updated.getForceLogoutAt(), "启用不应刷新 force_logout_at");
        assertEquals(1, updated.getTokenVersion().intValue(), "启用不应递增 token_version");
    }

    @Test
    void updateAffectedZeroRowsButDbAlreadyTargetIsIdempotent() {
        // 并发/重复提交：updateById 影响 0 行，但回查 DB 已是目标状态 → 幂等成功，不误报
        when(adminMapper.selectById(5)).thenReturn(admin(5, Admin.STATUS_DISABLED));
        when(adminMapper.updateById(org.mockito.ArgumentMatchers.any(Admin.class))).thenReturn(0);

        Map<String, Object> result = service.updateEmployeeStatus(5, Admin.STATUS_DISABLED, 999);

        assertEquals(Admin.STATUS_DISABLED, result.get("accountStatus"));
        verify(adminMapper, times(2)).selectById(5); // 初始查询 + 回查
    }

    @Test
    void updateAffectedZeroRowsAndDbUnchangedThrows() {
        // updateById 影响 0 行且 DB 仍是旧状态 → 明确报错，杜绝「返回成功但状态不变」
        // 注意：回查必须返回独立新对象（共享引用会被 setAccountStatus 改掉，导致回查误判幂等）
        when(adminMapper.selectById(5))
                .thenReturn(admin(5, Admin.STATUS_ACTIVE))
                .thenReturn(admin(5, Admin.STATUS_ACTIVE));
        when(adminMapper.updateById(org.mockito.ArgumentMatchers.any(Admin.class))).thenReturn(0);

        ApiException ex = assertThrows(ApiException.class,
                () -> service.updateEmployeeStatus(5, Admin.STATUS_DISABLED, 999));

        assertEquals(500, ex.getHttpStatus());
        assertEquals("ACCESS_STATUS_UPDATE_FAILED", ex.getErrorCode());
        assertTrue(String.valueOf(ex.getMessage()).contains("更新未生效"));
    }

    @Test
    void invalidStatusRejected() {
        when(adminMapper.selectById(5)).thenReturn(admin(5, Admin.STATUS_ACTIVE));

        ApiException ex = assertThrows(ApiException.class,
                () -> service.updateEmployeeStatus(5, "disabled", 999));

        assertEquals(400, ex.getHttpStatus());
        assertTrue(String.valueOf(ex.getMessage()).contains("无效的员工状态"));
        verify(adminMapper, never()).updateById(org.mockito.ArgumentMatchers.any(Admin.class));
    }

    @Test
    void cannotDisableSelf() {
        when(adminMapper.selectById(5)).thenReturn(admin(5, Admin.STATUS_ACTIVE));

        ApiException ex = assertThrows(ApiException.class,
                () -> service.updateEmployeeStatus(5, Admin.STATUS_DISABLED, 5));

        assertEquals(400, ex.getHttpStatus());
        assertTrue(String.valueOf(ex.getMessage()).contains("不能对当前登录账号"));
        verify(adminMapper, never()).updateById(org.mockito.ArgumentMatchers.any(Admin.class));
    }

    @Test
    void missingEmployeeThrowsNotFound() {
        when(adminMapper.selectById(99)).thenReturn(null);

        ApiException ex = assertThrows(ApiException.class,
                () -> service.updateEmployeeStatus(99, Admin.STATUS_DISABLED, 1));

        assertEquals(404, ex.getHttpStatus());
        assertTrue(String.valueOf(ex.getMessage()).contains("管理员不存在"));
        verify(adminMapper, never()).updateById(org.mockito.ArgumentMatchers.any(Admin.class));
    }

    @Test
    void nullOperatorSkipsSelfProtection() {
        // currentAdminId() 取不到时 operatorId=null：停用他人正常执行，不误伤
        when(adminMapper.selectById(5)).thenReturn(admin(5, Admin.STATUS_ACTIVE));
        when(adminMapper.updateById(org.mockito.ArgumentMatchers.any(Admin.class))).thenReturn(1);

        Map<String, Object> result = service.updateEmployeeStatus(5, Admin.STATUS_DISABLED, null);

        assertEquals(Admin.STATUS_DISABLED, result.get("accountStatus"));
        verify(adminMapper).updateById(org.mockito.ArgumentMatchers.any(Admin.class));
    }
}
