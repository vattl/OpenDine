package com.lanf.controller.admin;

import com.lanf.entity.AdminAppVersion;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.AdminAppVersionMapper;
import com.lanf.service.AdminPushDeviceService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminMobileAppControllerTest {

    @Test
    void registerPushDeviceUsesAuthenticatedAdminAndResolvedShop() {
        AdminPushController controller = new AdminPushController();
        AdminPushDeviceService service = mock(AdminPushDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        ReflectionTestUtils.setField(controller, "pushDeviceService", service);
        ReflectionTestUtils.setField(controller, "request", request);
        Map<String, Object> body = new HashMap<>();
        body.put("deviceToken", "token-1");
        body.put("platform", "android");
        body.put("channel", "huawei");
        body.put("appVersion", "2.0.1");
        body.put("deviceModel", "Mate 60");

        R result = controller.register(body);

        assertEquals(0, result.get("code"));
        verify(service).register(9, 7, "token-1", "android", "huawei", "2.0.1", "Mate 60");
    }

    @Test
    void preferenceRejectsInvalidNotificationType() {
        AdminPushController controller = new AdminPushController();
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        ReflectionTestUtils.setField(controller, "pushDeviceService", mock(AdminPushDeviceService.class));
        ReflectionTestUtils.setField(controller, "request", request);
        Map<String, Object> body = new HashMap<>();
        body.put("types", Arrays.asList("daily_settle", "bad/type"));

        R result = controller.preference(body);

        assertEquals(400, result.get("code"));
    }

    @SuppressWarnings("unchecked")
    @Test
    void versionReturnsMobileContractFieldNames() {
        AdminAppVersionController controller = new AdminAppVersionController();
        AdminAppVersionMapper mapper = mock(AdminAppVersionMapper.class);
        AdminAppVersion version = new AdminAppVersion();
        version.setLatest("2.1.0");
        version.setMin_supported("2.0.0");
        version.setForce_update(1);
        version.setRelease_notes("修复已知问题");
        version.setDownload_url("https://example.com/app");
        when(mapper.findCurrent("android", "mobile")).thenReturn(version);
        ReflectionTestUtils.setField(controller, "versionMapper", mapper);

        R result = controller.version("ANDROID", "mobile");
        Map<String, Object> data = (Map<String, Object>) result.get("data");

        assertEquals(0, result.get("code"));
        assertEquals("2.1.0", data.get("latest"));
        assertEquals("2.0.0", data.get("minSupported"));
        assertEquals(true, data.get("forceUpdate"));
    }
}
