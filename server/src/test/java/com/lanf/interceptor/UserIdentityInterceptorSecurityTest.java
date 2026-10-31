package com.lanf.interceptor;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.filter.CachedBodyHttpServletRequest;
import com.lanf.security.JwtTokenService;
import com.lanf.config.properties.UserIdentityCompatibilityProperties;
import com.lanf.interceptor.legacy.LegacyUserIdentityCompatibilityResolver;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.method.HandlerMethod;

import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UserIdentityInterceptorSecurityTest {

    private static final JwtTokenService TOKENS = new JwtTokenService(
            "test-user-secret-must-have-at-least-32-bytes", "");

    @Test
    void privateUserRouteRequiresTokenWhenNotWhitelisted() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/takeout/address/list");
        request.setRequestURI("/takeout/address/list");
        request.addParameter("openid", "victim");
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00").preHandle(request, response, handler()));
        assertEquals(401, responseBody(response).get("code"));
    }

    @Test
    void legacyWhitelistedRouteAllowsOpenidWithoutTokenAndAttachesIdentity() throws Exception {
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/create");
        raw.setRequestURI("/order/create");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\",\"shop_id\":1}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00");
        assertTrue(interceptor.preHandle(request, response, handler()));
        assertEquals("legacy-user", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void legacyPhoneBindingAllowedWhenCompatibilityEnabled() throws Exception {
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/getOfficialPhoneNumber");
        raw.setRequestURI("/order/getOfficialPhoneNumber");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\",\"code\":\"phone-code\"}"
                .getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);

        assertTrue(interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00").preHandle(request, new MockHttpServletResponse(), handler()));
        assertEquals("legacy-user", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void legacyWhitelistedRouteDeniedWhenCompatibilitySwitchDisabled() throws Exception {
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/create");
        raw.setRequestURI("/order/create");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\"}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(false, "2099-12-31T23:59:59+08:00");
        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(401, responseBody(response).get("code"));
    }

    @Test
    void legacyWhitelistedRouteDeniedWhenCompatibilityDeadlineExpired() throws Exception {
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/create");
        raw.setRequestURI("/order/create");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\"}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        // 截止时间设为过去时间
        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2020-01-01T00:00:00+08:00");
        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(401, responseBody(response).get("code"));
    }

    @Test
    void legacyNonWhitelistedRouteDeniedEvenIfOpenidProvided() throws Exception {
        // /order/refund/apply 不在白名单，旧版兼容不生效
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/refund/apply");
        raw.setRequestURI("/order/refund/apply");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\",\"order_no\":\"ORD-1\"}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00");
        assertFalse(interceptor.preHandle(request, response, handler()));
        assertEquals(401, responseBody(response).get("code"));
    }

    @Test
    void legacyPayByBalanceAllowedWhenOpenidProvided() throws Exception {
        // /order/payByBalance 已纳入旧版兼容白名单（携带 openid 即放行并绑定身份）
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/payByBalance");
        raw.setRequestURI("/order/payByBalance");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\",\"order_no\":\"ORD-1\"}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00");
        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), handler()));
        assertEquals("legacy-user", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void mismatchedBodyOpenidIsDeniedWhenTokenProvided() throws Exception {
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/history");
        raw.setRequestURI("/order/history");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"victim\"}".getBytes(StandardCharsets.UTF_8));
        raw.addHeader("X-User-Token", userToken("attacker"));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertFalse(interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00").preHandle(request, response, handler()));
        assertEquals(403, responseBody(response).get("code"));
    }

    @Test
    void matchingIdentityIsAttachedToRequest() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/takeout/address/list");
        request.setRequestURI("/takeout/address/list");
        request.addParameter("openid", "owner");
        request.addHeader("X-User-Token", userToken("owner"));

        assertTrue(interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00").preHandle(request, new MockHttpServletResponse(), handler()));
        assertEquals("owner", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void publicCatalogRouteDoesNotRequireUserToken() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/queue/config");
        request.setRequestURI("/queue/config");

        assertTrue(interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00").preHandle(request, new MockHttpServletResponse(), handler()));
    }

    @Test
    void publicTakeoutConfigRouteDoesNotRequireUserToken() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/order/takeout/config");
        request.setRequestURI("/order/takeout/config");

        assertTrue(interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00").preHandle(request, new MockHttpServletResponse(), handler()));
    }

    @Test
    void legacyGetOrderResolvesOpenidFromDatabaseResource() throws Exception {
        org.springframework.jdbc.core.JdbcTemplate mockJdbc = org.mockito.Mockito.mock(org.springframework.jdbc.core.JdbcTemplate.class);
        org.mockito.Mockito.when(mockJdbc.query(
                org.mockito.ArgumentMatchers.eq("SELECT openid FROM t_order WHERE order_no = ? ORDER BY id DESC LIMIT 1"),
                org.mockito.ArgumentMatchers.any(org.springframework.jdbc.core.RowMapper.class),
                org.mockito.ArgumentMatchers.eq("ORD-888")
        )).thenReturn(Collections.singletonList("resolved-order-owner"));

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00", mockJdbc);

        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/order/getOrder");
        request.setRequestURI("/order/getOrder");
        request.addParameter("order_no", "ORD-888");
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertTrue(interceptor.preHandle(request, response, handler()));
        assertEquals("resolved-order-owner", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void legacyTakeoutAddressSaveAllowedWithoutToken() throws Exception {
        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/takeout/address/save");
        raw.setRequestURI("/order/takeout/address/save");
        raw.setContentType("application/json");
        raw.setContent("{\"openid\":\"legacy-user\",\"contact_name\":\"张三\",\"contact_phone\":\"13800000000\"}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00");
        assertTrue(interceptor.preHandle(request, response, handler()));
        assertEquals("legacy-user", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void legacyTakeoutAddressListAllowedWithoutToken() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/order/takeout/address/list");
        request.setRequestURI("/order/takeout/address/list");
        request.addParameter("openid", "legacy-user");
        MockHttpServletResponse response = new MockHttpServletResponse();

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00");
        assertTrue(interceptor.preHandle(request, response, handler()));
        assertEquals("legacy-user", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void legacyTakeoutAddressDeleteResolvesOpenidFromResource() throws Exception {
        org.springframework.jdbc.core.JdbcTemplate mockJdbc = org.mockito.Mockito.mock(org.springframework.jdbc.core.JdbcTemplate.class);
        org.mockito.Mockito.when(mockJdbc.query(
                org.mockito.ArgumentMatchers.eq("SELECT openid FROM t_user_address WHERE id = ? ORDER BY id DESC LIMIT 1"),
                org.mockito.ArgumentMatchers.any(org.springframework.jdbc.core.RowMapper.class),
                org.mockito.ArgumentMatchers.eq("88")
        )).thenReturn(Collections.singletonList("address-owner-openid"));

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00", mockJdbc);

        MockHttpServletRequest raw = new MockHttpServletRequest("POST", "/order/takeout/address/delete");
        raw.setRequestURI("/order/takeout/address/delete");
        raw.setContentType("application/json");
        raw.setContent("{\"id\":88}".getBytes(StandardCharsets.UTF_8));
        CachedBodyHttpServletRequest request = new CachedBodyHttpServletRequest(raw);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertTrue(interceptor.preHandle(request, response, handler()));
        assertEquals("address-owner-openid", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    @Test
    void legacyGetOrderByTableResolvesOpenidFromDatabaseResource() throws Exception {
        org.springframework.jdbc.core.JdbcTemplate mockJdbc = org.mockito.Mockito.mock(org.springframework.jdbc.core.JdbcTemplate.class);
        org.mockito.Mockito.when(mockJdbc.query(
                org.mockito.ArgumentMatchers.eq("SELECT openid FROM t_order WHERE table_number = ? AND transac_status = ? ORDER BY id DESC LIMIT 1"),
                org.mockito.ArgumentMatchers.any(org.springframework.jdbc.core.RowMapper.class),
                org.mockito.ArgumentMatchers.eq("A01"),
                org.mockito.ArgumentMatchers.eq("unsettled")
        )).thenReturn(Collections.singletonList("table-owner-openid"));

        UserIdentityInterceptor interceptor = interceptorWithCompatibility(true, "2099-12-31T23:59:59+08:00", mockJdbc);

        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/order/get");
        request.setRequestURI("/order/get");
        request.addParameter("table_number", "A01");
        request.addParameter("transac_status", "unsettled");
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertTrue(interceptor.preHandle(request, response, handler()));
        assertEquals("table-owner-openid", request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID));
    }

    private static UserIdentityInterceptor interceptorWithCompatibility(boolean enabled, String deadline) {
        return interceptorWithCompatibility(enabled, deadline, null);
    }

    private static UserIdentityInterceptor interceptorWithCompatibility(boolean enabled, String deadline,
                                                                        org.springframework.jdbc.core.JdbcTemplate jdbcTemplate) {
        UserIdentityCompatibilityProperties props = new UserIdentityCompatibilityProperties();
        props.setCompatibilityEnabled(enabled);
        props.setCompatibilityDeadline(deadline);

        LegacyUserIdentityCompatibilityResolver resolver = new LegacyUserIdentityCompatibilityResolver(props, jdbcTemplate);

        UserIdentityInterceptor interceptor = new UserIdentityInterceptor();
        ReflectionTestUtils.setField(interceptor, "jwtTokenService", TOKENS);
        ReflectionTestUtils.setField(interceptor, "legacyCompatibilityResolver", resolver);
        return interceptor;
    }

    private static String userToken(String openid) {
        return TOKENS.createToken(openid, "user", 60_000, Collections.emptyMap());
    }

    private static HandlerMethod handler() throws NoSuchMethodException {
        return new HandlerMethod(new TestController(), TestController.class.getDeclaredMethod("handle"));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> responseBody(MockHttpServletResponse response) throws Exception {
        return new ObjectMapper().readValue(response.getContentAsString(), Map.class);
    }

    private static final class TestController {
        public void handle() {
        }
    }
}
