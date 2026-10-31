package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierOrderRebuildControllerTest {

    @Test
    @SuppressWarnings("unchecked")
    void details_shouldReturnFormalIdsRefundStateAndClientMapping() {
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);
        Order order = new Order();
        order.setId(9001);
        order.setShop_id(7);
        order.setOrder_no("ORD-9001");
        order.setDineInOrTakeOut("堂食");
        order.setOrder_time(new Date(1786572600000L));
        OrderDetail line = new OrderDetail();
        line.setId(9901);
        line.setDish_id(101);
        line.setName("油边王");
        line.setQuantity("1");
        line.setRefunded_quantity(1);
        line.setClient_line_id("line-1");
        when(orders.getOne(any(Wrapper.class))).thenReturn(order);
        when(details.list(any(Wrapper.class))).thenReturn(Collections.singletonList(line));
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        R result = new CashierOrderRebuildController(orders, details).details(9001, request);

        assertEquals(0, result.get("code"));
        assertEquals("dine_in", ((Map<String, Object>) result.get("order")).get("fulfillment_type"));
        Map<String, Object> returned = ((List<Map<String, Object>>) result.get("lines")).get(0);
        assertEquals(9901, returned.get("detail_id"));
        assertEquals(2, returned.get("quantity"));
        assertEquals(1, returned.get("refunded_quantity"));
        assertEquals(1, returned.get("remaining_quantity"));
        assertEquals("line-1", returned.get("client_line_id"));
    }

    @Test
    void details_shouldRejectMissingShopContextWithoutQuerying() {
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);

        R result = new CashierOrderRebuildController(orders, details)
                .details(9001, new MockHttpServletRequest());

        assertEquals(4001, result.get("code"));
        verify(orders, never()).getOne(any(Wrapper.class));
    }
}
