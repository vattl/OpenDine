package com.lanf.integration.web;

import com.lanf.config.ZsqSystemSettings;
import com.lanf.integration.service.*;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ZsqConfigProxyRetirementTest {
    @Test void retiredRouteReturnsHttp410WithBothExceptionAdvices() throws Exception {
        ZsqAuthService auth = mock(ZsqAuthService.class);
        org.springframework.test.web.servlet.MockMvc mvc = org.springframework.test.web.servlet.setup.MockMvcBuilders
                .standaloneSetup(new ZsqAuthController(auth,new ZsqSystemSettings(true,true)))
                .setControllerAdvice(new com.lanf.config.GlobalApiExceptionHandler(),new GlobalExceptionHandler()).build();
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/api/zsq/auth/login/config"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isGone());
        verifyNoInteractions(auth);
    }
    @Test void configLoginCannotDiscloseServerCredentials() {
        ZsqAuthService auth = mock(ZsqAuthService.class);
        ZsqAuthController controller = new ZsqAuthController(auth, new ZsqSystemSettings(true, true));
        ResponseStatusException ex = assertThrows(ResponseStatusException.class, controller::loginByConfig);
        assertEquals(410, ex.getStatus().value());
        verifyNoInteractions(auth);
    }
    @Test void autoRoutesNeverCallServerAccountServices() {
        ZsqOrderService orders = mock(ZsqOrderService.class);
        ZsqDeliveryService delivery = mock(ZsqDeliveryService.class);
        ZsqOrderController controller = new ZsqOrderController(orders, delivery, new ZsqSystemSettings(true, true));
        assertThrows(ResponseStatusException.class, () -> controller.createTakeawayAuto(null));
        assertThrows(ResponseStatusException.class, () -> controller.createTakeawayAndDispatchAuto(null));
        assertThrows(ResponseStatusException.class, () -> controller.riderTrackingAuto(1));
        verifyNoInteractions(orders, delivery);
    }
}
