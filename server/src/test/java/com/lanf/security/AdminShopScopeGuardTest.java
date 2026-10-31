package com.lanf.security;

import com.lanf.constant.AdminDataScope;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IAdminShopAccessService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AdminShopScopeGuardTest {

    @Test
    void shopAdminCannotSelectGlobalOrAnotherShop() {
        AdminShopScopeGuard guard = guard(AdminDataScope.SHOP, 7);
        int[] target = new int[1];

        assertEquals(4003, guard.resolveTargetShopId(0, target).get("code"));
        assertEquals(4003, guard.resolveTargetShopId(8, target).get("code"));
    }

    @Test
    void shopAdminDefaultsToAuthenticatedShopContext() {
        AdminShopScopeGuard guard = guard(AdminDataScope.SHOP, 7);
        int[] target = new int[1];

        assertNull(guard.resolveTargetShopId(null, target));
        assertEquals(7, target[0]);
    }

    @Test
    void headquartersAdminMaySelectGlobalConfiguration() {
        AdminShopScopeGuard guard = guard(AdminDataScope.HQ, null);
        int[] target = new int[1];

        assertNull(guard.resolveTargetShopId(0, target));
        assertEquals(0, target[0]);
        assertNull(guard.requireHeadquarters());
    }

    private static AdminShopScopeGuard guard(AdminDataScope scope, Integer resolvedShopId) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 3);
        if (resolvedShopId != null) {
            request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, resolvedShopId);
        }
        IAdminShopAccessService access = mock(IAdminShopAccessService.class);
        when(access.resolveScope(3)).thenReturn(scope);
        when(access.listAccessibleShopIds(3)).thenReturn(
                resolvedShopId == null ? Collections.emptySet() : Collections.singleton(resolvedShopId));
        return new AdminShopScopeGuard(request, access);
    }
}
