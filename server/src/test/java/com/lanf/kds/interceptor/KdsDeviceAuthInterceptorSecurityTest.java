package com.lanf.kds.interceptor;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class KdsDeviceAuthInterceptorSecurityTest {

    @Test
    void heartbeatWithoutDeviceTokenIsRejected() throws Exception {
        KdsDeviceAuthInterceptor interceptor = new KdsDeviceAuthInterceptor();
        ReflectionTestUtils.setField(interceptor, "deviceService", mock(KdsDeviceService.class));
        ReflectionTestUtils.setField(interceptor, "objectMapper", new ObjectMapper());
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/kds/device/heartbeat");
        request.setServletPath("/kds/device/heartbeat");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, new Object());

        assertFalse(allowed, "心跳接口必须使用已绑定设备令牌，不能匿名调用");
        assertEquals(401, response.getStatus());
    }

    @Test
    void loginPrefixPathIsNotWhitelisted() throws Exception {
        KdsDeviceAuthInterceptor interceptor = new KdsDeviceAuthInterceptor();
        ReflectionTestUtils.setField(interceptor, "deviceService", mock(KdsDeviceService.class));
        ReflectionTestUtils.setField(interceptor, "objectMapper", new ObjectMapper());
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/kds/device/login-legacy");
        request.setServletPath("/kds/device/login-legacy");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, new Object());

        assertFalse(allowed, "公开登录白名单必须精确匹配，不能放行相同路径前缀");
        assertEquals(401, response.getStatus());
    }

    @Test
    void cashierForwardedShopContextMustMatchCloudDeviceBinding() throws Exception {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDevice device = new KdsDevice();
        device.setShop_id(7);
        when(deviceService.findByToken("cloud-token")).thenReturn(device);
        KdsDeviceAuthInterceptor interceptor = new KdsDeviceAuthInterceptor();
        ReflectionTestUtils.setField(interceptor, "deviceService", deviceService);
        ReflectionTestUtils.setField(interceptor, "objectMapper", new ObjectMapper());
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/kds/v2/changes");
        request.setServletPath("/kds/v2/changes");
        request.addHeader("X-Kds-Device-Token", "cloud-token");
        request.addHeader("X-Shop-Id", "8");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, new Object());

        assertFalse(allowed);
        assertEquals(403, response.getStatus());
    }

    @Test
    void queryDeviceTokenIsRejectedEvenIfValid() throws Exception {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDevice device = new KdsDevice();
        device.setShop_id(7);
        when(deviceService.findByToken("cloud-token")).thenReturn(device);
        KdsDeviceAuthInterceptor interceptor = new KdsDeviceAuthInterceptor();
        ReflectionTestUtils.setField(interceptor, "deviceService", deviceService);
        ReflectionTestUtils.setField(interceptor, "objectMapper", new ObjectMapper());
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/kds/v2/bootstrap");
        request.setServletPath("/kds/v2/bootstrap");
        request.setParameter("device_token", "cloud-token");
        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, new Object());

        assertFalse(allowed, "HTTP 接口必须退役 URL query token，不能允许通过 query 参数携带令牌通过鉴权");
        assertEquals(401, response.getStatus());
    }
}
