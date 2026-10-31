package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.service.IAnalyticsService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class AdminAnalyticsAndOrderReportTimeTest {

    private AdminAnalyticsController analyticsController;
    private AdminOrderController orderController;
    private IAnalyticsService analyticsService;
    private IOrderService orderService;
    private IShopService shopService;

    @BeforeEach
    void setUp() {
        analyticsController = new AdminAnalyticsController();
        analyticsService = mock(IAnalyticsService.class);
        shopService = mock(IShopService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Shop-Id", "1");
        request.setAttribute(com.lanf.interceptor.SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        ReflectionTestUtils.setField(analyticsController, "analyticsService", analyticsService);
        ReflectionTestUtils.setField(analyticsController, "shopService", shopService);
        ReflectionTestUtils.setField(analyticsController, "httpServletRequest", request);

        orderController = new AdminOrderController();
        orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(orderController, "orderService", orderService);
        ReflectionTestUtils.setField(orderController, "shopService", shopService);
        ReflectionTestUtils.setField(orderController, "httpServletRequest", request);
    }

    @Test
    @DisplayName("AdminAnalyticsController.business: 纯日期参数自动按门店 settle_time 补全为营业日区间")
    void analyticsBusinessPureDateAutoCompletes() {
        when(analyticsService.businessOverview(any(), any(), eq(1))).thenReturn(Collections.emptyMap());

        R r = analyticsController.business("2026-10-08", "2026-10-08", null, null, null, null);
        assertEquals(0, r.get("code"));

        verify(analyticsService).businessOverview("2026-10-08 04:00:00", "2026-10-09 04:00:00", 1);
    }

    @Test
    @DisplayName("AdminAnalyticsController.business: 自定义带时分秒参数保留指定时间")
    void analyticsBusinessCustomTimePreserved() {
        when(analyticsService.businessOverview(any(), any(), eq(1))).thenReturn(Collections.emptyMap());

        R r = analyticsController.business("2026-10-08 10:00:00", "2026-10-08 22:00:00", null, null, null, null);
        assertEquals(0, r.get("code"));

        verify(analyticsService).businessOverview("2026-10-08 10:00:00", "2026-10-08 22:00:00", 1);
    }

    @Test
    @DisplayName("AdminAnalyticsController.customers: 参数别名 startDate/endDate 纯日期支持")
    void analyticsCustomersAliasSupported() {
        when(analyticsService.customerAnalysis(any(), any(), eq(1))).thenReturn(Collections.emptyMap());

        R r = analyticsController.customers(null, null, "2026-10-02", "2026-10-08", null, null);
        assertEquals(0, r.get("code"));

        verify(analyticsService).customerAnalysis("2026-10-02 04:00:00", "2026-10-09 04:00:00", 1);
    }

    @Test
    @DisplayName("AdminOrderController.statisticsCategorySales: 纯日期参数补全为营业日区间")
    void orderStatisticsCategorySalesPureDate() {
        when(orderService.statisticsCategorySales(any())).thenReturn(Collections.emptyList());
        when(orderService.statisticsOrderSummary(any())).thenReturn(Collections.emptyMap());

        R r = orderController.statisticsCategorySales(null, null, "2026-10-08", "2026-10-08", null, null, null);
        assertEquals(0, r.get("code"));

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(orderService).statisticsCategorySales(captor.capture());
        Map<String, Object> params = captor.getValue();
        assertEquals("2026-10-08 04:00:00", params.get("startTime"));
        assertEquals("2026-10-09 04:00:00", params.get("endTime"));
    }

    @Test
    @DisplayName("AdminOrderController.statisticsDishSales: 自定义时分秒保留输入")
    void orderStatisticsDishSalesCustomTime() {
        when(orderService.statisticsDishSales(any())).thenReturn(Collections.emptyList());

        R r = orderController.statisticsDishSales("2026-10-08 11:30:00", "2026-10-08 21:30:00", null, null, null, null, null);
        assertEquals(0, r.get("code"));

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(orderService).statisticsDishSales(captor.capture());
        Map<String, Object> params = captor.getValue();
        assertEquals("2026-10-08 11:30:00", params.get("startTime"));
        assertEquals("2026-10-08 21:30:00", params.get("endTime"));
    }
}
