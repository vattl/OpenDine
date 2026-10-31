package com.lanf.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.OperationLog;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOperationLogService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class SecurityAuditServiceTest {

    @Test
    void deniedAuditContainsIdentityResourceAndDecisionButNotCredentials() {
        IOperationLogService logs = mock(IOperationLogService.class);
        SecurityAuditService service = new SecurityAuditService(logs, new ObjectMapper());
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/admin/rbac/roles");
        request.addHeader("Authorization", "Bearer must-not-be-logged");
        request.setAttribute(SysInterceptor.ATTR_TRACE_ID, "trace-1");
        request.setRemoteAddr("127.0.0.1");

        service.recordAccessDenied(request, 7, 3, 403, "permission_denied", "admin:manage");

        ArgumentCaptor<OperationLog> captor = ArgumentCaptor.forClass(OperationLog.class);
        verify(logs).save(captor.capture());
        OperationLog row = captor.getValue();
        assertEquals("security", row.getModule());
        assertEquals("access_denied", row.getAction());
        assertEquals(7, row.getAdmin_id());
        assertEquals(3, row.getShop_id());
        assertEquals("trace-1", row.getTrace_id());
        assertTrue(row.getRequest_snapshot().contains("admin:manage"));
        assertFalse(row.getRequest_snapshot().contains("must-not-be-logged"));
    }

    @Test
    void permissionMutationStoresOnlyCallerSuppliedSafeState() {
        IOperationLogService logs = mock(IOperationLogService.class);
        SecurityAuditService service = new SecurityAuditService(logs, new ObjectMapper());
        MockHttpServletRequest request = new MockHttpServletRequest("PUT", "/admin/administrator/9/roles");
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_TRACE_ID, "trace-2");

        service.recordPermissionChange(request, "admin_roles_changed", "9",
                Collections.singletonMap("roleIds", Collections.singletonList(2)),
                Collections.singletonMap("roleIds", Arrays.asList(3, 4)));

        ArgumentCaptor<OperationLog> captor = ArgumentCaptor.forClass(OperationLog.class);
        verify(logs).save(captor.capture());
        OperationLog row = captor.getValue();
        assertEquals(1, row.getAdmin_id());
        assertEquals("SUCCESS", row.getResult_status());
        assertTrue(row.getBefore_state().contains("2"));
        assertTrue(row.getAfter_state().contains("3"));
    }

    @Test
    void persistenceFailureDoesNotBypassOrBreakAuthorizationFlow() {
        IOperationLogService logs = mock(IOperationLogService.class);
        when(logs.save(any())).thenThrow(new IllegalStateException("database unavailable"));
        SecurityAuditService service = new SecurityAuditService(logs, new ObjectMapper());

        assertDoesNotThrow(() -> service.recordAccessDenied(
                new MockHttpServletRequest("GET", "/admin/order/list"),
                null, null, 401, "missing_authorization", null));
    }
}
