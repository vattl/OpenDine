package com.lanf.controller.admin;

import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.integration.exception.ZsqRemoteOrderMissingException;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.ITakeoutZsqIntegrationService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AdminTakeoutControllerTrackingTest {

    @Test
    void returnsRedispatchActionWhenRemoteOrderWasDeleted() {
        AdminTakeoutController controller = new AdminTakeoutController();
        IOrderService orderService = mock(IOrderService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        ITakeoutZsqIntegrationService integrationService = mock(ITakeoutZsqIntegrationService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "takeoutZsqIntegrationService", integrationService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        Order order = new Order();
        order.setId(13573);
        order.setShop_id(1);
        order.setDineInOrTakeOut("外卖");
        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(13573);
        delivery.setZsq_dispatch_status("order_missing");
        when(orderService.getById(13573)).thenReturn(order);
        when(deliveryService.getByOrderId(13573)).thenReturn(delivery);
        when(integrationService.getTrackingForOrder(13573))
                .thenThrow(new ZsqRemoteOrderMissingException(54159992L, null));

        R response = controller.deliveryTracking(13573);

        assertEquals(4091, response.get("code"));
        assertEquals(ZsqRemoteOrderMissingException.USER_MESSAGE, response.get("msg"));
        assertEquals(true, response.get("canRedispatch"));
        assertEquals("/admin/takeout/delivery/zsq/redispatch", response.get("redispatchUrl"));
        assertSame(delivery, response.get("delivery"));
    }
}
