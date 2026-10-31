package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsWorkflowV2Service;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminPosCommandControllerTest {

    @Test
    void adminPosEntryStillDelegatesFinancialCommandWithResolvedShop() {
        KdsWorkflowV2Service service = mock(KdsWorkflowV2Service.class);
        AdminPosCommandController controller = new AdminPosCommandController();
        ReflectionTestUtils.setField(controller, "kdsWorkflowV2Service", service);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 12);
        Map<String, Object> body = new HashMap<>();
        body.put("command_id", "pos-admin-add-1");
        body.put("type", "pos_add_dishes");
        when(service.executeCommand(org.mockito.ArgumentMatchers.any(KdsDevice.class),
                org.mockito.ArgumentMatchers.eq(body)))
                .thenReturn(Collections.singletonMap("accepted", true));

        R result = controller.posCommands(body, request);

        assertEquals(0, result.get("code"));
        assertEquals(true, result.get("accepted"));
        ArgumentCaptor<KdsDevice> deviceCaptor = ArgumentCaptor.forClass(KdsDevice.class);
        verify(service).executeCommand(deviceCaptor.capture(), org.mockito.ArgumentMatchers.eq(body));
        assertEquals(12, deviceCaptor.getValue().getShop_id());
        assertEquals("pos-admin", deviceCaptor.getValue().getDevice_code());
    }
}
