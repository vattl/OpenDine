package com.lanf.controller.admin;

import com.lanf.entity.Admin;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.IAdminService;
import com.lanf.util.AdminPasswordUtil;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminControllerSecurityTest {

    @Test
    void passwordChangeTargetsAuthenticatedAdminAndRevokesExistingTokens() {
        IAdminService adminService = mock(IAdminService.class);
        Admin stored = storedAdmin();
        when(adminService.getById(7)).thenReturn(stored);
        when(adminService.updateById(any(Admin.class))).thenReturn(true);
        AdminController controller = controller(adminService);

        Admin input = new Admin();
        input.setUserName("another-admin");
        input.setPassword("old-password");
        input.setNewPassword("new-password");
        R result = controller.modifyPassword(input, authenticatedRequest());

        assertEquals(0, result.get("code"));
        ArgumentCaptor<Admin> updated = ArgumentCaptor.forClass(Admin.class);
        verify(adminService).updateById(updated.capture());
        assertEquals(7, updated.getValue().getId());
        assertEquals(5, updated.getValue().getTokenVersion());
        org.junit.jupiter.api.Assertions.assertTrue(
                AdminPasswordUtil.matches("new-password", updated.getValue().getPassword()));
    }

    @Test
    void passwordChangeRejectsWrongCurrentPassword() {
        IAdminService adminService = mock(IAdminService.class);
        when(adminService.getById(7)).thenReturn(storedAdmin());
        AdminController controller = controller(adminService);
        Admin input = new Admin();
        input.setPassword("wrong-password");
        input.setNewPassword("new-password");

        R result = controller.modifyPassword(input, authenticatedRequest());

        org.junit.jupiter.api.Assertions.assertNotEquals(0, result.get("code"));
        verify(adminService, never()).updateById(any(Admin.class));
    }

    private static Admin storedAdmin() {
        Admin admin = new Admin();
        admin.setId(7);
        admin.setUserName("current-admin");
        admin.setPassword(AdminPasswordUtil.encode("old-password"));
        admin.setTokenVersion(4);
        return admin;
    }

    private static AdminController controller(IAdminService adminService) {
        AdminController controller = new AdminController();
        ReflectionTestUtils.setField(controller, "adminService", adminService);
        ReflectionTestUtils.setField(controller, "securityAuditService", mock(SecurityAuditService.class));
        return controller;
    }

    private static MockHttpServletRequest authenticatedRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 7);
        return request;
    }
}
