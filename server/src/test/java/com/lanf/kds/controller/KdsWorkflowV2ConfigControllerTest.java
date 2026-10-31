package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.util.KdsDeviceAuth;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsWorkflowV2ConfigControllerTest {

    @Test
    void ordinaryKdsDeviceCannotMutateShopLevelConfig() {
        KdsWorkflowV2Controller controller = new KdsWorkflowV2Controller();
        KdsDeviceAuth auth = mock(KdsDeviceAuth.class);
        KdsSettingsController settings = mock(KdsSettingsController.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        KdsDevice device = new KdsDevice();
        device.setShop_id(7);
        device.setDevice_code("KDS-07");
        Map<String, Object> body = Collections.<String, Object>singletonMap("enable_prep_workflow", 1);
        when(auth.requireDevice(request)).thenReturn(device);
        ReflectionTestUtils.setField(controller, "deviceAuth", auth);
        ReflectionTestUtils.setField(controller, "settingsController", settings);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.config(body, response);

        assertEquals(4030, result.get("code"));
        assertEquals(403, response.getStatus());
        verify(settings, never()).saveForDevice(device, body);
    }

    @Test
    void configReturnsHttp401WhenDeviceTokenIsInvalid() {
        KdsWorkflowV2Controller controller = new KdsWorkflowV2Controller();
        KdsDeviceAuth auth = mock(KdsDeviceAuth.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        when(auth.requireDevice(request)).thenThrow(new IllegalStateException("invalid device token"));
        ReflectionTestUtils.setField(controller, "deviceAuth", auth);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.config(Collections.emptyMap(), response);

        assertEquals(401, result.get("code"));
        assertEquals(401, response.getStatus());
    }
}
