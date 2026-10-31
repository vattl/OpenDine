package com.lanf.receivable;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.receivable.controller.AdminReceivableController;
import com.lanf.receivable.entity.ReceivableAccount;
import com.lanf.receivable.mapper.ReceivableAccountMapper;
import com.lanf.receivable.mapper.ReceivableClaimMapper;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Collections;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class AdminReceivableAccountManagementTest {

    private ReceivableService service;
    private ReceivableAccountMapper accountMapper;
    private ReceivableClaimMapper claimMapper;
    private AdminReceivableController controller;
    private HttpServletRequest request;
    private IAdminPermissionService permissionService;
    private IAdminShopAccessService shopAccessService;

    @BeforeEach
    void setUp() {
        service = new ReceivableService();
        accountMapper = mock(ReceivableAccountMapper.class);
        claimMapper = mock(ReceivableClaimMapper.class);
        ReflectionTestUtils.setField(service, "accountMapper", accountMapper);
        ReflectionTestUtils.setField(service, "claimMapper", claimMapper);
        ReflectionTestUtils.setField(service, "clock", Clock.fixed(
                Instant.parse("2026-10-19T05:00:00Z"), ZoneId.of("Asia/Shanghai")));

        controller = new AdminReceivableController();
        request = mock(HttpServletRequest.class);
        permissionService = mock(IAdminPermissionService.class);
        shopAccessService = mock(IAdminShopAccessService.class);

        ReflectionTestUtils.setField(controller, "receivableService", service);
        ReflectionTestUtils.setField(controller, "request", request);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "adminShopAccessService", shopAccessService);
    }

    @Test
    void deleteAccount_withOutstandingBalance_throws409() {
        ReceivableAccount account = new ReceivableAccount();
        account.setId(101L);
        account.setMerchantId("1");
        account.setShopId(1);
        account.setScopeType(ReceivableAccount.SCOPE_SHOP);
        account.setOutstandingFen(5000L); // 50.00 outstanding
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);

        ApiException ex = assertThrows(ApiException.class, () ->
                service.deleteAccount(1, 9, "1", 101L));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("RECEIVABLE_ACCOUNT_HAS_BALANCE", ex.getErrorCode());
        verify(accountMapper, never()).deleteById(anyLong());
    }

    @Test
    void deleteAccount_withActiveClaims_throws409() {
        ReceivableAccount account = new ReceivableAccount();
        account.setId(102L);
        account.setMerchantId("1");
        account.setShopId(1);
        account.setScopeType(ReceivableAccount.SCOPE_SHOP);
        account.setOutstandingFen(0L);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(claimMapper.selectCount(any(Wrapper.class))).thenReturn(1); // 1 active claim

        ApiException ex = assertThrows(ApiException.class, () ->
                service.deleteAccount(1, 9, "1", 102L));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("RECEIVABLE_ACCOUNT_HAS_BALANCE", ex.getErrorCode());
        verify(accountMapper, never()).deleteById(anyLong());
    }

    @Test
    void deleteAccount_noHistoricalClaims_physicallyDeletes() {
        ReceivableAccount account = new ReceivableAccount();
        account.setId(103L);
        account.setMerchantId("1");
        account.setShopId(1);
        account.setScopeType(ReceivableAccount.SCOPE_SHOP);
        account.setOutstandingFen(0L);
        account.setStatus(ReceivableAccount.STATUS_ACTIVE);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(claimMapper.selectCount(any(Wrapper.class))).thenReturn(0); // 0 active, 0 total
        when(accountMapper.deleteById(103L)).thenReturn(1);

        Map<String, Object> result = service.deleteAccount(1, 9, "1", 103L);
        assertTrue((Boolean) result.get("deleted"));
        assertFalse((Boolean) result.get("closed"));
        verify(accountMapper, times(1)).deleteById(103L);
    }

    @Test
    void deleteAccount_withHistoricalSettledClaims_safelyClosesAccount() {
        ReceivableAccount account = new ReceivableAccount();
        account.setId(104L);
        account.setMerchantId("1");
        account.setShopId(1);
        account.setScopeType(ReceivableAccount.SCOPE_SHOP);
        account.setOutstandingFen(0L);
        account.setStatus(ReceivableAccount.STATUS_ACTIVE);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        // First count for active claims returns 0; second count for total claims returns 5
        when(claimMapper.selectCount(any(Wrapper.class))).thenReturn(0, 5);
        when(accountMapper.updateById(any(ReceivableAccount.class))).thenReturn(1);

        Map<String, Object> result = service.deleteAccount(1, 9, "1", 104L);
        assertFalse((Boolean) result.get("deleted"));
        assertTrue((Boolean) result.get("closed"));
        assertEquals(ReceivableAccount.STATUS_CLOSED, account.getStatus());
        assertNotNull(account.getClosedAt());
        verify(accountMapper, never()).deleteById(anyLong());
        verify(accountMapper, times(1)).updateById(account);
    }

    @Test
    void controller_deleteAccount_withoutPermission_throws403() {
        when(request.getAttribute(SysInterceptor.ATTR_ADMIN_ID)).thenReturn(12);
        when(request.getHeader("X-Shop-Id")).thenReturn("1");
        when(permissionService.getPermissionCodesByAdminId(12)).thenReturn(Collections.singleton("order:view"));
        when(shopAccessService.isSuperAdmin(12)).thenReturn(false);

        ApiException ex = assertThrows(ApiException.class, () -> controller.deleteAccount(101L));
        assertEquals(403, ex.getHttpStatus());
        assertEquals("RECEIVABLE_PERMISSION_DENIED", ex.getErrorCode());
    }

    @Test
    void controller_deleteAccount_withManagePermission_succeeds() {
        when(request.getAttribute(SysInterceptor.ATTR_ADMIN_ID)).thenReturn(10);
        when(request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID)).thenReturn(1);
        when(permissionService.getPermissionCodesByAdminId(10)).thenReturn(Collections.singleton("receivable:manage"));

        ReceivableAccount account = new ReceivableAccount();
        account.setId(105L);
        account.setMerchantId("1");
        account.setShopId(1);
        account.setScopeType(ReceivableAccount.SCOPE_SHOP);
        account.setOutstandingFen(0L);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(claimMapper.selectCount(any(Wrapper.class))).thenReturn(0);
        when(accountMapper.deleteById(105L)).thenReturn(1);

        R response = controller.deleteAccount(105L);
        assertEquals(0, response.get("code"));
        assertTrue((Boolean) response.get("deleted"));
    }
}
