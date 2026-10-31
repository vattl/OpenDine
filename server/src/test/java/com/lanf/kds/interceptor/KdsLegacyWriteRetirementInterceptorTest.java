package com.lanf.kds.interceptor;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsLegacyWriteRetirementInterceptorTest {

    private ObjectMapper objectMapper;
    private KdsLegacyWriteRetirementInterceptor interceptor;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
        interceptor = new KdsLegacyWriteRetirementInterceptor(objectMapper);
    }

    @Test
    void rejectsLegacyBusinessWritesWithGoneContract() throws Exception {
        assertRetired("POST", "/kds/item/status");
        assertRetired("POST", "/kds/workflow/advance-item");
        assertRetired("POST", "/kds/order/rush");
        assertRetired("POST", "/kds/grill/start-cooking");
        assertRetired("POST", "/kds/expedition/serve");
        assertRetired("POST", "/kds/skewer/picked");
        assertRetired("POST", "/kds/sync/all");
        assertRetired("PUT", "/kds/settings");
        assertRetired("POST", "/api/v1/kds/advance-item");
    }

    @Test
    void preservesCanonicalV2AndDeviceLifecycleWrites() throws Exception {
        assertAllowed("POST", "/kds/v2/commands");
        assertAllowed("POST", "/kds/v2/config");
        assertAllowed("POST", "/kds/device/login");
        assertAllowed("POST", "/kds/device/heartbeat");
        assertAllowed("POST", "/api/v1/kds/device/login");
        assertAllowed("POST", "/api/v1/kds/devices/heartbeat");
    }

    @Test
    void preservesReadsAndNonKdsRequests() throws Exception {
        assertAllowed("GET", "/kds/item/list");
        assertAllowed("GET", "/kds/workflow/board");
        assertAllowed("GET", "/api/v1/kds/tickets");
        assertAllowed("POST", "/admin/kds/device/bind");
        assertAllowed("OPTIONS", "/kds/item/status");
    }

    private void assertRetired(String method, String path) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setServletPath(path);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptor.preHandle(request, response, new Object()));
        assertEquals(410, response.getStatus());
        assertEquals("application/json;charset=UTF-8", response.getContentType());
        Map<String, Object> body = objectMapper.readValue(
                response.getContentAsString(),
                new TypeReference<Map<String, Object>>() {
                });
        assertEquals(410, ((Number) body.get("code")).intValue());
        assertEquals("旧版 KDS 写接口已停用，请升级并使用 /kds/v2/commands", body.get("msg"));
    }

    private void assertAllowed(String method, String path) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setServletPath(path);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertTrue(interceptor.preHandle(request, response, new Object()));
        assertEquals(200, response.getStatus());
    }
}
