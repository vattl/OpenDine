package com.lanf.config;

import com.lanf.entity.ApiPermission;
import com.lanf.mapper.ApiPermissionMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class DbApiPermissionMappingSecurityTest {

    @Test
    void wildcardMethodAndSinglePathSegmentFollowDatabaseContract() {
        DbApiPermissionMapping mapping = mapping(
                entry("*", "/admin/order/list", "order:view"),
                entry("GET", "/cashier/orders/*/details", "cashier:operate"));

        assertEquals("order:view", mapping.getRequiredPermission("GET", "/admin/order/list"));
        assertEquals("order:view", mapping.getRequiredPermission("POST", "/admin/order/list"));
        assertEquals("cashier:operate", mapping.getRequiredPermission("GET", "/cashier/orders/123/details"));
        assertNull(mapping.getRequiredPermission("POST", "/cashier/orders/123/details"));
        assertNull(mapping.getRequiredPermission("GET", "/cashier/orders/123/extra/details"));
    }

    @Test
    void exactDatabasePathDoesNotAuthorizeSimilarPrefix() {
        DbApiPermissionMapping mapping = mapping(
                entry("*", "/admin/config/feieyun", "admin:manage"),
                entry("*", "/admin/administrator/", "admin:manage"));

        assertNull(mapping.getRequiredPermission("GET", "/admin/config/feieyun-legacy"));
        assertEquals("admin:manage", mapping.getRequiredPermission("PUT", "/admin/administrator/7/roles"));
    }

    @Test
    void failedReloadPreservesLastSuccessfulAuthoritativeSnapshot() {
        ApiPermissionMapper mapper = mock(ApiPermissionMapper.class);
        when(mapper.selectList(any()))
                .thenReturn(Arrays.asList(entry("*", "/admin/order/list", "order:view")))
                .thenThrow(new IllegalStateException("database unavailable"));
        DbApiPermissionMapping mapping = new DbApiPermissionMapping();
        ReflectionTestUtils.setField(mapping, "apiPermissionMapper", mapper);

        mapping.reload();
        mapping.reload();

        assertEquals("order:view", mapping.getRequiredPermission("GET", "/admin/order/list"));
    }

    private static DbApiPermissionMapping mapping(ApiPermission... entries) {
        ApiPermissionMapper mapper = mock(ApiPermissionMapper.class);
        when(mapper.selectList(any())).thenReturn(Arrays.asList(entries));
        DbApiPermissionMapping mapping = new DbApiPermissionMapping();
        ReflectionTestUtils.setField(mapping, "apiPermissionMapper", mapper);
        mapping.reload();
        return mapping;
    }

    private static ApiPermission entry(String method, String path, String permission) {
        ApiPermission entry = new ApiPermission();
        entry.setMethod(method);
        entry.setPath_pattern(path);
        entry.setPermission_code(permission);
        return entry;
    }
}
