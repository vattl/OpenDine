package com.lanf.kds.controller.admin;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsPairingTicketService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminKdsControllerTest {

    @Test
    void devicePairingTicketIsCloudIssuedForResolvedShopAndAuditedAdmin() {
        AdminKdsController controller = new AdminKdsController();
        KdsPairingTicketService pairingTickets = mock(KdsPairingTicketService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 19);
        ReflectionTestUtils.setField(controller, "pairingTicketService", pairingTickets);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
        when(pairingTickets.issue(7, "KDS-01", "admin:19"))
                .thenReturn(new KdsPairingTicketService.PairingTicket(
                        "KDS-01", "ABCDEFGH", 123456789L));

        R result = controller.devicePairingTicket(
                Collections.singletonMap("device_code", "KDS-01"));

        assertEquals(0, result.get("code"));
        Map<?, ?> data = (Map<?, ?>) result.get("data");
        assertEquals("ABCDEFGH", data.get("pairing_code"));
        assertEquals(123456789L, data.get("expires_at_ms"));
        verify(pairingTickets).issue(7, "KDS-01", "admin:19");
    }

    @Test
    @DisplayName("deviceList：管理端设备视图不得泄露鉴权 Token")
    void deviceListDoesNotExposeDeviceToken() {
        AdminKdsController controller = new AdminKdsController();
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(controller, "deviceService", deviceService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        KdsDevice device = new KdsDevice();
        device.setId(9L);
        device.setShop_id(1);
        device.setDevice_code("KDS-SECURE-01");
        device.setDevice_token("must-never-leave-cloud");
        device.setEnabled(1);
        when(deviceService.listByShop(1)).thenReturn(Collections.singletonList(device));

        R result = controller.deviceList();

        assertEquals(0, result.get("code"));
        List<?> list = (List<?>) result.get("list");
        Map<?, ?> view = (Map<?, ?>) list.get(0);
        assertEquals("KDS-SECURE-01", view.get("device_code"));
        assertEquals(false, view.containsKey("device_token"));
        assertEquals(false, view.containsKey("deviceToken"));
    }

    @Test
    void proxyCommandCannotAuthorizeKdsOperations() {
        AdminKdsController controller = new AdminKdsController();
        Map<String, Object> command = new HashMap<>();
        command.put("command_id", "command-01");
        command.put("type", "advance_item");
        Map<String, Object> body = new HashMap<>();
        body.put("actor_device_code", "KDS-01");
        body.put("command", command);

        R result = controller.deviceProxyCommand(body);

        assertEquals(410, result.get("code"));
    }

    @Test
    @DisplayName("deviceProxyLogin：旧的收银代签 Token 能力永久停用")
    void deviceProxyLoginIsRetired() {
        AdminKdsController controller = new AdminKdsController();

        R result = controller.deviceProxyLogin(
                Collections.singletonMap("device_code", "KDS-PROXY-01"));

        assertEquals(410, result.get("code"));
    }

    @Test
    @DisplayName("deviceBind：忽略客户端伪造 Token，只允许云端签发")
    void deviceBindIgnoresClientSuppliedToken() {
        AdminKdsController controller = new AdminKdsController();
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        ReflectionTestUtils.setField(controller, "deviceService", deviceService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        KdsDevice mockDevice = new KdsDevice();
        mockDevice.setId(15L);
        mockDevice.setShop_id(1);
        mockDevice.setDevice_code("KDS-4A8F7CCD");
        mockDevice.setDevice_token("eskXpMa56QlYa5YzGSEKxRiOCAtuHhZ56pwYFRIKqhg");
        mockDevice.setScreen_tag("workflow_board");
        mockDevice.setScreen_tags(Collections.singletonList("meat_grill"));
        mockDevice.setWorkflows(Arrays.asList("cook", "serve"));

        when(deviceService.bindMetadata(eq(1), eq("KDS-4A8F7CCD"), eq("热菜档口屏"), eq("workflow_board"),
                eq(Collections.singletonList("meat_grill"))))
                .thenReturn(mockDevice);
        when(deviceService.enrichWorkflows(any(KdsDevice.class))).thenReturn(mockDevice);

        Map<String, Object> body = new HashMap<>();
        body.put("deviceCode", "KDS-4A8F7CCD");
        body.put("deviceName", "热菜档口屏");
        body.put("screenTag", "workflow_board");
        body.put("screenTags", Collections.singletonList("meat_grill"));
        body.put("deviceToken", "eskXpMa56QlYa5YzGSEKxRiOCAtuHhZ56pwYFRIKqhg");
        body.put("workflows", Arrays.asList("cook", "serve"));

        R result = controller.deviceBind(body);

        assertEquals(0, result.get("code"));
        Map<?, ?> deviceView = (Map<?, ?>) result.get("device");
        assertNotNull(deviceView);
        assertEquals(false, deviceView.containsKey("device_token"));
        assertEquals(false, deviceView.containsKey("deviceToken"));
        verify(deviceService).bindMetadata(eq(1), eq("KDS-4A8F7CCD"), eq("热菜档口屏"), eq("workflow_board"),
                eq(Collections.singletonList("meat_grill")));
        verify(deviceService).saveWorkflowSelection(eq(15L), eq(Arrays.asList("cook", "serve")));
    }

    @Test
    @DisplayName("deviceUnbind：支持根据 device_code 真正删除设备")
    void deviceUnbindByDeviceCodeDeletesDevice() {
        AdminKdsController controller = new AdminKdsController();
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        ReflectionTestUtils.setField(controller, "deviceService", deviceService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        Map<String, Object> body = new HashMap<>();
        body.put("device_code", "KDS-DEL-01");
        R result = controller.deviceUnbind(body, null, null, null, null, null);

        assertEquals(0, result.get("code"));
        verify(deviceService).deleteDevice(2, "KDS-DEL-01");
    }

    @Test
    @DisplayName("deviceUnbind：支持根据 id 真正删除设备")
    void deviceUnbindByIdDeletesDevice() {
        AdminKdsController controller = new AdminKdsController();
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        ReflectionTestUtils.setField(controller, "deviceService", deviceService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        Map<String, Object> body = new HashMap<>();
        body.put("id", 101);
        R result = controller.deviceUnbind(body, null, null, null, null, null);

        assertEquals(0, result.get("code"));
        verify(deviceService).deleteDeviceById(2, 101L);
    }

    @Test
    @DisplayName("deviceUnbind：支持通过 Query 参数传递 id 删除")
    void deviceDeleteByQueryParams() {
        AdminKdsController controller = new AdminKdsController();
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        ReflectionTestUtils.setField(controller, "deviceService", deviceService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        R result = controller.deviceUnbind(null, 55L, null, null, null, null);

        assertEquals(0, result.get("code"));
        verify(deviceService).deleteDeviceById(2, 55L);
    }

    @Test
    @DisplayName("deviceUnbind：参数缺失返回错误")
    void deviceUnbindMissingParamsReturnsError() {
        AdminKdsController controller = new AdminKdsController();
        KdsDeviceService deviceService = mock(KdsDeviceService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        ReflectionTestUtils.setField(controller, "deviceService", deviceService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        R result = controller.deviceUnbind(Collections.emptyMap(), null, null, null, null, null);

        assertEquals(500, result.get("code"));
    }
}

