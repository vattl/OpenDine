package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.report.service.ReportOrderAggregate;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.*;

class AdminReportControllerBusinessReportTest {
    private AdminReportController controller;
    private ReportOrderAggregate aggregate;
    private IOrderService orderService;
    private IShopService shopService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminReportController();
        aggregate = mock(ReportOrderAggregate.class);
        orderService = mock(IOrderService.class);
        shopService = mock(IShopService.class);
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Shop shop = new Shop();
        shop.setId(7);
        shop.setSettle_time("04:00");
        when(shopService.getById(7)).thenReturn(shop);

        ReflectionTestUtils.setField(controller, "reportOrderAggregate", aggregate);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void dailyPassesBusinessDateToFinancialAggregateWithoutLoadingOrders() {
        when(aggregate.row(7, "2026-10-02", "2026-10-02 04:00:00", "2026-10-03 04:00:00"))
                .thenReturn(Arrays.asList("2026-10-02", "2", "95.00", "91.00", "10.00", "5.00", "3.00"));

        R response = controller.daily("2026-10-02");

        Map<?, ?> report = (Map<?, ?>) response.get("report");
        assertEquals(91.0d, report.get("totalAmount"));
        assertEquals(2L, report.get("orderCount"));
        verifyNoInteractions(orderService);
    }

    @Test
    void weeklyUsesInclusiveBusinessDateRangeWithExclusiveNextDayBoundary() {
        when(aggregate.row(7, "2026-10-01~2026-10-07", "2026-10-01 04:00:00", "2026-10-08 04:00:00"))
                .thenReturn(Arrays.asList("week", "8", "560.00", "520.00", "20.00", "10.00", "30.00"));

        R response = controller.weekly("2026-10-01", "2026-10-07");

        Map<?, ?> report = (Map<?, ?>) response.get("report");
        assertEquals(520.0d, report.get("totalAmount"));
        assertEquals(8L, report.get("orderCount"));
        verifyNoInteractions(orderService);
    }

    @Test
    void monthlyUsesBusinessDatesFromFirstThroughLastCalendarDate() {
        when(aggregate.row(7, "2026-02", "2026-02-01 04:00:00", "2026-03-01 04:00:00"))
                .thenReturn(Arrays.asList("month", "28", "900.00", "880.00", "10.00", "5.00", "15.00"));

        R response = controller.monthly(2026, 2);

        Map<?, ?> report = (Map<?, ?>) response.get("report");
        assertEquals(880.0d, report.get("totalAmount"));
        assertEquals(28L, report.get("orderCount"));
        verifyNoInteractions(orderService);
    }

    @Test
    void headquartersAggregatesEachShopUsingItsOwnSettlementTime() {
        request.removeAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        Shop shopAtTwo = new Shop();
        shopAtTwo.setId(11);
        shopAtTwo.setSettle_time("02:00");
        Shop shopAtFive = new Shop();
        shopAtFive.setId(12);
        shopAtFive.setSettle_time("05:00");
        when(shopService.list()).thenReturn(Arrays.asList(shopAtTwo, shopAtFive));
        when(aggregate.row(11, "2026-10-02", "2026-10-02 02:00:00", "2026-10-03 02:00:00"))
                .thenReturn(Arrays.asList("2026-10-02", "2", "100.00", "90.00", "0.00", "0.00", "10.00"));
        when(aggregate.row(12, "2026-10-02", "2026-10-02 05:00:00", "2026-10-03 05:00:00"))
                .thenReturn(Arrays.asList("2026-10-02", "3", "220.00", "200.00", "0.00", "0.00", "20.00"));

        R response = controller.daily("2026-10-02");

        Map<?, ?> report = (Map<?, ?>) response.get("report");
        assertEquals(290.0d, report.get("totalAmount"));
        assertEquals(5L, report.get("orderCount"));
        verifyNoInteractions(orderService);
    }
}
