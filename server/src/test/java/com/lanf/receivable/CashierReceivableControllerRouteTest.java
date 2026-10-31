package com.lanf.receivable;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.receivable.controller.CashierReceivableController;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.lang.reflect.Method;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierReceivableControllerRouteTest {

    @Test
    void eligibleAccountsRouteIsRegisteredAndReturnsEmptyListForShopWithoutAccounts() throws Exception {
        assertNotNull(CashierReceivableController.class.getAnnotation(RestController.class));
        RequestMapping root = CashierReceivableController.class.getAnnotation(RequestMapping.class);
        assertNotNull(root);
        assertEquals("/cashier/receivables", root.value()[0]);
        Method method = CashierReceivableController.class.getMethod("eligibleAccounts");
        GetMapping route = method.getAnnotation(GetMapping.class);
        assertNotNull(route);
        assertEquals("/eligible-accounts", route.value()[0]);

        CashierReceivableController controller = new CashierReceivableController();
        ReceivableService receivableService = mock(ReceivableService.class);
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        IAdminShopAccessService shopAccessService = mock(IAdminShopAccessService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 5);
        when(permissionService.getPermissionCodesByAdminId(9))
                .thenReturn(Collections.singleton("receivable:view"));
        when(receivableService.eligibleAccounts("1", 5)).thenReturn(Collections.emptyList());
        ReflectionTestUtils.setField(controller, "receivableService", receivableService);
        ReflectionTestUtils.setField(controller, "request", request);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "adminShopAccessService", shopAccessService);

        R result = controller.eligibleAccounts();

        assertEquals(0, result.get("code"));
        assertTrue(((java.util.List<?>) result.get("accounts")).isEmpty());
        verify(receivableService).eligibleAccounts("1", 5);
    }
}
