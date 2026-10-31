package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminOrderControllerTodayUnsettledTest {

    private AdminOrderController controller;
    private IOrderService orderService;
    private IShopService shopService;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private com.lanf.kds.service.KdsOrderEnrichService kdsOrderEnrichService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminOrderController();
        orderService = mock(IOrderService.class);
        shopService = mock(IShopService.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        kdsOrderEnrichService = mock(com.lanf.kds.service.KdsOrderEnrichService.class);
        request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(controller, "kdsOrderEnrichService", kdsOrderEnrichService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void todayUnsettledAmount_shouldFilterMerchantId1() {
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        Shop shop = new Shop();
        shop.setId(2);
        shop.setSettle_time("04:00");
        shop.setOpen_time("16:00");
        when(shopService.getById(2)).thenReturn(shop);

        Order order = new Order();
        order.setId(101);
        order.setMerchantId("1");
        order.setTransac_status("unsettled");
        order.setSett_amount(88.50d);
        order.setDiscount_amount(0d);
        order.setService_fee(5.0d);
        order.setRefund_amount(0d);
        order.setPay_amount_gift(0d);

        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));

        R res = controller.todayUnsettledAmount(null);

        assertEquals(0, res.get("code"));
        assertEquals(93.5, ((Number) res.get("todayUnsettledAmount")).doubleValue(), 0.001);
        assertEquals(1, res.get("todayUnsettledCount"));

        ArgumentCaptor<QueryWrapper<Order>> captor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(orderService).list(captor.capture());
        QueryWrapper<Order> wrapper = captor.getValue();
        String sqlSegment = wrapper.getCustomSqlSegment();
        // 验证生成的 SQL 条件中包含 merchantId 与 transac_status
        assertTrue(sqlSegment.contains("merchantId"));
        assertTrue(sqlSegment.contains("transac_status"));
        assertTrue(wrapper.getParamNameValuePairs().containsValue("1"));
        assertTrue(wrapper.getParamNameValuePairs().containsValue("unsettled"));
    }

    @Test
    void list_withoutParams_defaultsToOperationalWindow() {
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        Shop shop = new Shop();
        shop.setId(2);
        shop.setSettle_time("04:00");
        when(shopService.getById(2)).thenReturn(shop);
        when(orderService.list(any(Map.class))).thenReturn(Collections.emptyList());
        when(orderService.getTotal(any(Map.class))).thenReturn(0L);
        when(orderService.getTodayOrderCount(2)).thenReturn(0L);

        R res = controller.list(null);

        assertEquals(0, res.get("code"));
        String startTime = (String) res.get("startTime");
        String endTime = (String) res.get("endTime");
        assertNotNull(startTime);
        assertNotNull(endTime);
        assertTrue(startTime.endsWith("04:00:00"), "startTime should end with settle_time 04:00:00");
        assertTrue(endTime.endsWith("04:00:00"), "endTime should end with settle_time 04:00:00");

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> mapCaptor = ArgumentCaptor.forClass(Map.class);
        verify(orderService).list(mapCaptor.capture());
        Map<String, Object> capturedMap = mapCaptor.getValue();
        assertEquals(startTime, capturedMap.get("startTime"));
        assertEquals(endTime, capturedMap.get("endTime"));
        assertEquals(2, capturedMap.get("shop_id"));
    }
}
