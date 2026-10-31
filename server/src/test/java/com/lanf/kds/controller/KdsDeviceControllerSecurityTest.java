package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsPairingTicketService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.Collections;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsDeviceControllerSecurityTest {

    @Test
    void existingDeviceCodeAloneCannotRotateToken() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDevice existing = existingDevice();
        when(deviceService.findByDeviceCode("kds-01")).thenReturn(existing);
        KdsDeviceController controller = controller(deviceService, new MockHttpServletRequest());

        R result = controller.login(validLoginBody());

        assertEquals(403, result.get("code"));
        verify(deviceService, never()).bind(anyInt(), anyString(), anyString(), anyString(), anyList());
    }

    @Test
    void existingDeviceMayRotateWithItsCurrentValidToken() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDevice existing = existingDevice();
        KdsDevice rotated = existingDevice();
        rotated.setDevice_token("rotated-token");
        when(deviceService.findByDeviceCode("kds-01")).thenReturn(existing);
        when(deviceService.findByToken("current-token")).thenReturn(existing);
        when(deviceService.loginBoundDevice(
                1, "kds-01", "后厨屏", "cook", Collections.emptyList(), null))
                .thenReturn(rotated);
        when(deviceService.enrichWorkflows(rotated)).thenReturn(rotated);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Kds-Device-Token", "current-token");
        KdsDeviceController controller = controller(deviceService, request);

        R result = controller.login(validLoginBody());

        assertEquals(0, result.get("code"));
        verify(deviceService).loginBoundDevice(
                1, "kds-01", "后厨屏", "cook", Collections.emptyList(), null);
    }

    @Test
    void proxiedLoginShopHeaderMustMatchCloudDeviceBinding() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDevice existing = existingDevice();
        when(deviceService.findByDeviceCode("kds-01")).thenReturn(existing);
        when(deviceService.findByToken("current-token")).thenReturn(existing);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Kds-Device-Token", "current-token");
        request.addHeader("X-Shop-Id", "2");
        KdsDeviceController controller = controller(deviceService, request);

        R result = controller.login(validLoginBody());

        assertEquals(403, result.get("code"));
        verify(deviceService, never()).bind(anyInt(), anyString(), anyString(), anyString(), anyList());
    }

    @Test
    void missingPairingSecretCannotBindDevice() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDeviceController controller = controller(deviceService, new MockHttpServletRequest());

        R result = controller.login(validLoginBody());

        assertEquals(403, result.get("code"));
        verify(deviceService, never()).bind(anyInt(), anyString(), anyString(), anyString());
    }

    @Test
    void oneTimePairingCodeLogsInOnlyPreBoundDevice() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsPairingTicketService pairingTickets = mock(KdsPairingTicketService.class);
        KdsDevice device = existingDevice();
        when(deviceService.findByDeviceCode("kds-01")).thenReturn(existingDevice());
        when(pairingTickets.consumeAndLogin(
                "ABCDEFGH", "kds-01", "后厨屏", "cook", Collections.emptyList()))
                .thenReturn(device);
        when(deviceService.enrichWorkflows(device)).thenReturn(device);
        Map<String, Object> body = validLoginBody();
        body.put("pairing_code", "ABCDEFGH");
        KdsDeviceController controller = controller(
                deviceService, pairingTickets, new MockHttpServletRequest());

        R result = controller.login(body);

        assertEquals(0, result.get("code"));
        verify(pairingTickets).consumeAndLogin(
                "ABCDEFGH", "kds-01", "后厨屏", "cook", Collections.emptyList());
    }

    @Test
    void pairingCodeCannotImplicitlyCreateUnknownDevice() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsPairingTicketService pairingTickets = mock(KdsPairingTicketService.class);
        Map<String, Object> body = validLoginBody();
        body.put("pairing_code", "ABCDEFGH");
        KdsDeviceController controller = controller(
                deviceService, pairingTickets, new MockHttpServletRequest());

        R result = controller.login(body);

        assertEquals(403, result.get("code"));
        verify(pairingTickets, never()).consumeAndLogin(
                anyString(), anyString(), anyString(), anyString(), anyList());
    }

    @Test
    void heartbeatUsesAuthenticatedDeviceInsteadOfRequestDeviceCode() {
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        KdsDeviceAuth deviceAuth = mock(KdsDeviceAuth.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        KdsDevice authenticated = new KdsDevice();
        authenticated.setDevice_code("trusted-kds");
        when(deviceAuth.requireDevice(request)).thenReturn(authenticated);
        KdsDeviceController controller = controller(deviceService, request);
        ReflectionTestUtils.setField(controller, "deviceAuth", deviceAuth);
        Map<String, Object> attackerBody = new HashMap<>();
        attackerBody.put("deviceCode", "another-shop-kds");

        R result = controller.heartbeat(attackerBody);

        assertEquals(0, result.get("code"));
        verify(deviceService).heartbeat("trusted-kds");
        verify(deviceService, never()).heartbeat("another-shop-kds");
    }

    private static KdsDeviceController controller(KdsDeviceService service,
                                                   MockHttpServletRequest request) {
        return controller(service, mock(KdsPairingTicketService.class), request);
    }

    private static KdsDeviceController controller(KdsDeviceService service,
                                                   KdsPairingTicketService pairingTickets,
                                                   MockHttpServletRequest request) {
        KdsDeviceController controller = new KdsDeviceController();
        ReflectionTestUtils.setField(controller, "deviceService", service);
        ReflectionTestUtils.setField(controller, "pairingTicketService", pairingTickets);
        ReflectionTestUtils.setField(controller, "request", request);
        return controller;
    }

    private static Map<String, Object> validLoginBody() {
        Map<String, Object> body = new HashMap<>();
        body.put("shopId", 1);
        body.put("deviceCode", "kds-01");
        body.put("deviceName", "后厨屏");
        body.put("screenTag", "cook");
        return body;
    }

    private static KdsDevice existingDevice() {
        KdsDevice device = new KdsDevice();
        device.setId(11L);
        device.setShop_id(1);
        device.setDevice_code("kds-01");
        device.setDevice_name("后厨屏");
        device.setScreen_tag("cook");
        device.setEnabled(1);
        return device;
    }
}
