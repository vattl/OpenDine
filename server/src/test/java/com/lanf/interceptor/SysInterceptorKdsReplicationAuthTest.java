package com.lanf.interceptor;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class SysInterceptorKdsReplicationAuthTest {

    @Test
    @SuppressWarnings("unchecked")
    void replicationAuthFailuresUseHttpStatusAndStableOutboxCode() throws Exception {
        SysInterceptor interceptor = new SysInterceptor();
        MockHttpServletResponse unauthorized = new MockHttpServletResponse();
        MockHttpServletResponse forbidden = new MockHttpServletResponse();

        ReflectionTestUtils.invokeMethod(interceptor, "writeReplicationAwareJson",
                unauthorized, "/admin/kds/replication/events", 401, "expired");
        ReflectionTestUtils.invokeMethod(interceptor, "writeReplicationAwareJson",
                forbidden, "/admin/kds/replication/events", 403, "forbidden");

        Map<String, Object> unauthorizedBody = new ObjectMapper().readValue(
                unauthorized.getContentAsString(), Map.class);
        Map<String, Object> forbiddenBody = new ObjectMapper().readValue(
                forbidden.getContentAsString(), Map.class);
        assertEquals(401, unauthorized.getStatus());
        assertEquals(4010, unauthorizedBody.get("code"));
        assertEquals(403, forbidden.getStatus());
        assertEquals(4010, forbiddenBody.get("code"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void missingShopContextIsPermanent400ForReplication() throws Exception {
        SysInterceptor interceptor = new SysInterceptor();
        MockHttpServletResponse response = new MockHttpServletResponse();

        ReflectionTestUtils.invokeMethod(interceptor, "writeReplicationAwareJson",
                response, "/admin/kds/replication/events", 4001, "missing shop");

        Map<String, Object> body = new ObjectMapper().readValue(response.getContentAsString(), Map.class);
        assertEquals(400, response.getStatus());
        assertEquals(4000, body.get("code"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void batchAuthFailureUsesOutboxStableCode() throws Exception {
        SysInterceptor interceptor = new SysInterceptor();
        MockHttpServletResponse response = new MockHttpServletResponse();
        ReflectionTestUtils.invokeMethod(interceptor, "writeReplicationAwareJson",
                response, "/admin/kds/replication/events/batch", 401, "expired");
        Map<String, Object> body = new ObjectMapper().readValue(response.getContentAsString(), Map.class);
        assertEquals(401, response.getStatus());
        assertEquals(4010, body.get("code"));
    }
}
