package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsSettingsControllerSecurityTest {

    @Test
    void authenticatedDeviceCannotReadAnotherShopSettingsOrPin() {
        KdsConfigService configService = mock(KdsConfigService.class);
        KdsDeviceAuth deviceAuth = mock(KdsDeviceAuth.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        KdsDevice device = new KdsDevice();
        device.setShop_id(1);
        device.setDevice_code("KDS-01");
        when(deviceAuth.requireDevice(request)).thenReturn(device);

        KdsShopConfig ownConfig = new KdsShopConfig();
        ownConfig.setShop_id(1);
        ownConfig.setKds_pin("654321");
        ownConfig.setSla_minutes(12);
        when(configService.getOrDefault(1)).thenReturn(ownConfig);

        KdsSettingsController controller = new KdsSettingsController();
        ReflectionTestUtils.setField(controller, "configService", configService);
        ReflectionTestUtils.setField(controller, "deviceAuth", deviceAuth);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.get(2, null);

        assertEquals(403, result.get("code"));
        assertFalse(result.containsKey("config"));
        assertFalse(result.toString().contains("654321"));
        verify(configService, never()).getOrDefault(2);
    }

    @Test
    void settingsResponseUsesAuthenticatedShopAndNeverSerializesRawConfig() {
        KdsConfigService configService = mock(KdsConfigService.class);
        KdsDeviceAuth deviceAuth = mock(KdsDeviceAuth.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        KdsDevice device = new KdsDevice();
        device.setShop_id(7);
        when(deviceAuth.requireDevice(request)).thenReturn(device);

        KdsShopConfig config = new KdsShopConfig();
        config.setShop_id(7);
        config.setKds_pin("987654");
        config.setSla_minutes(9);
        when(configService.getOrDefault(7)).thenReturn(config);

        KdsSettingsController controller = new KdsSettingsController();
        ReflectionTestUtils.setField(controller, "configService", configService);
        ReflectionTestUtils.setField(controller, "deviceAuth", deviceAuth);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.get(null, null);

        assertEquals(0, result.get("code"));
        assertFalse(result.containsKey("config"));
        assertFalse(result.toString().contains("987654"));
        @SuppressWarnings("unchecked")
        Map<String, Object> settings = (Map<String, Object>) result.get("settings");
        assertEquals(7, settings.get("shop_id"));
        assertEquals(9, settings.get("sla_minutes"));
        assertTrue(settings.containsKey("enable_prep_workflow"));
        verify(configService).getOrDefault(7);
    }
}
