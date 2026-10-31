package com.lanf.controller.admin;

import com.lanf.dto.DishSalesDTO;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.report.service.ReportOrderAggregate;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.IDailyCloseService;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AdminReportControllerDailyReportTest {

    private AdminReportController controller;
    private ReportOrderAggregate aggregate;
    private IOrderService orderService;
    private IShopService shopService;
    private IDailyCloseService dailyCloseService;
    private IMemberRechargeService memberRechargeService;
    private IUserService userService;
    private ReceivableService receivableService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminReportController();
        aggregate = mock(ReportOrderAggregate.class);
        orderService = mock(IOrderService.class);
        shopService = mock(IShopService.class);
        dailyCloseService = mock(IDailyCloseService.class);
        memberRechargeService = mock(IMemberRechargeService.class);
        userService = mock(IUserService.class);
        receivableService = mock(ReceivableService.class);
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Shop shop = new Shop();
        shop.setId(7);
        shop.setName("总店 / 旗舰店");
        shop.setSettle_time("04:00");
        when(shopService.getById(7)).thenReturn(shop);

        ReflectionTestUtils.setField(controller, "reportOrderAggregate", aggregate);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "dailyCloseService", dailyCloseService);
        ReflectionTestUtils.setField(controller, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "receivableService", receivableService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
        when(receivableService.summarizeWindow(any(), any(), any(), any()))
                .thenReturn(ReceivableWindowSummary.empty());
    }

    @Test
    void dailyDefaultDetailFalseReturnsAggregateWithGrossDiscountRefund() {
        when(aggregate.row(7, "2026-10-02", "2026-10-02 04:00:00", "2026-10-03 04:00:00"))
                .thenReturn(Arrays.asList("2026-10-02", "2", "95.00", "91.00", "10.00", "5.00", "3.00"));

        R response = controller.daily("2026-10-02");

        Map<?, ?> report = (Map<?, ?>) response.get("report");
        assertNotNull(report);
        assertEquals(91.0d, report.get("totalAmount"));
        assertEquals(2L, report.get("orderCount"));
        assertEquals(95.0d, report.get("grossRevenue"));
        assertEquals(91.0d, report.get("netRevenue"));
        assertEquals(10.0d, report.get("totalDiscount"));
        assertEquals(3.0d, report.get("totalRefund"));
        assertNotNull(report.get("receivableSummary"));
        assertEquals(9100L, report.get("totalCollectionsFen"));
        verifyNoInteractions(orderService);
    }

    @Test
    void dailyDetailTrueReturnsEightCommercialDimensions() {
        // Mock Z-Report
        Map<String, Object> zReport = new LinkedHashMap<>();
        zReport.put("is_closed", true);
        zReport.put("report_type", "Z_REPORT");
        zReport.put("snapshot_no", "DSN2026100200078832");
        zReport.put("operator_name", "店长张华");
        zReport.put("closed_at", new Date());

        List<Map<String, Object>> channels = new ArrayList<>();
        Map<String, Object> ch1 = new LinkedHashMap<>();
        ch1.put("code", "wechat_native");
        ch1.put("label", "微信支付");
        ch1.put("net_amount_fen", 5000L);
        ch1.put("success_count", 1);
        ch1.put("refund_count", 0);
        channels.add(ch1);
        zReport.put("channels", channels);

        Map<String, Object> drawer = new LinkedHashMap<>();
        drawer.put("opening_float_fen", 20000L);
        drawer.put("counted_cash_fen", 24100L);
        drawer.put("total_variance_fen", 0L);
        drawer.put("sessions_count", 1L);
        zReport.put("drawer_summary", drawer);
        Map<String, Object> receivable = new LinkedHashMap<>();
        receivable.put("charged_fen", 10000L);
        receivable.put("collected_fen", 4000L);
        receivable.put("writeoff_fen", 500L);
        receivable.put("reversed_fen", 1000L);
        receivable.put("outstanding_fen", 4500L);
        receivable.put("cutoff_ledger_id", 19L);
        zReport.put("receivable_summary", receivable);
        zReport.put("total_collections_fen", 9000L);
        zReport.put("printable_text", "=== Z REPORT ===");

        when(dailyCloseService.generateZReport(eq(7), eq("2026-10-02"))).thenReturn(zReport);

        // Mock Orders
        Order o1 = new Order();
        o1.setId(101);
        o1.setSett_amount(50.0);
        o1.setService_fee(0.0);
        o1.setDiscount_amount(5.0);
        o1.setRefund_amount(0.0);
        o1.setNumber_of_diners("2");
        o1.setDineInOrTakeOut("堂食");
        o1.setPayment_method("微信支付");

        Order o2 = new Order();
        o2.setId(102);
        o2.setSett_amount(45.0);
        o2.setService_fee(0.0);
        o2.setDiscount_amount(5.0);
        o2.setRefund_amount(3.0);
        o2.setNumber_of_diners("2");
        o2.setDineInOrTakeOut("堂食");
        o2.setPayment_method("现金");

        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Arrays.asList(o1, o2));

        // Mock Dish Sales
        DishSalesDTO d1 = new DishSalesDTO();
        d1.setDish_name("招牌秘制烤羊肉串");
        d1.setTotal_quantity(12L);
        d1.setTotal_sales("48.00");
        when(orderService.statisticsDishSales(any())).thenReturn(Collections.singletonList(d1));

        R response = controller.daily("2026-10-02", null, null, null, true);

        assertEquals(0, response.get("code"));
        Map<?, ?> report = (Map<?, ?>) response.get("report");
        assertNotNull(report);

        // Check top-level compatibility
        assertEquals(2L, report.get("orderCount"));

        // Check 1. Metadata
        Map<?, ?> meta = (Map<?, ?>) report.get("metadata");
        assertNotNull(meta);
        assertEquals(7, meta.get("shopId"));
        assertEquals("2026-10-02", meta.get("businessDay"));
        assertEquals(true, meta.get("isSettled"));
        assertEquals("Z_REPORT", meta.get("reportType"));
        assertEquals("DSN2026100200078832", meta.get("snapshotNo"));

        // Check 2. Summary
        Map<?, ?> summary = (Map<?, ?>) report.get("summary");
        assertNotNull(summary);
        assertEquals(2L, summary.get("orderCount"));
        assertEquals(4L, summary.get("dinerCount"));
        assertEquals(10.0d, summary.get("totalDiscount"));
        assertEquals(3.0d, summary.get("totalRefund"));

        // Check 3. Payment Channels
        List<?> paymentChannels = (List<?>) report.get("paymentChannels");
        assertNotNull(paymentChannels);
        assertFalse(paymentChannels.isEmpty());

        Map<?, ?> receivableSummary = (Map<?, ?>) report.get("receivableSummary");
        assertNotNull(receivableSummary);
        assertEquals(10000L, receivableSummary.get("chargedFen"));
        assertEquals(4000L, receivableSummary.get("collectedFen"));
        assertEquals(500L, receivableSummary.get("writeoffFen"));
        assertEquals(1000L, receivableSummary.get("reversedFen"));
        assertEquals(4500L, receivableSummary.get("outstandingFen"));
        assertEquals(9000L, report.get("totalCollectionsFen"));
        assertEquals(90.0d, report.get("totalCollections"));

        // Check 4. Cash Drawer
        Map<?, ?> cashDrawer = (Map<?, ?>) report.get("cashDrawer");
        assertNotNull(cashDrawer);
        assertEquals(200.0d, cashDrawer.get("openingFloat"));
        assertEquals(241.0d, cashDrawer.get("countedCash"));
        assertEquals(0.0d, cashDrawer.get("variance"));

        // Check 5. Order Types
        List<?> orderTypes = (List<?>) report.get("orderTypes");
        assertNotNull(orderTypes);
        assertEquals(3, orderTypes.size());

        // Check 6. Member
        Map<?, ?> member = (Map<?, ?>) report.get("member");
        assertNotNull(member);

        // Check 7. Exceptions
        Map<?, ?> exceptions = (Map<?, ?>) report.get("exceptions");
        assertNotNull(exceptions);
        assertEquals(1L, exceptions.get("refundCount"));
        assertEquals(3.0d, exceptions.get("refundAmount"));

        // Check 8. Top Dishes
        List<?> topDishes = (List<?>) report.get("topDishes");
        assertNotNull(topDishes);
        assertEquals(1, topDishes.size());
        Map<?, ?> topDish = (Map<?, ?>) topDishes.get(0);
        assertEquals("招牌秘制烤羊肉串", topDish.get("dishName"));
        assertEquals(12L, topDish.get("quantity"));

        // Verify shopId and shop_id are passed to statisticsDishSales for multi-store isolation
        @SuppressWarnings("unchecked")
        org.mockito.ArgumentCaptor<Map<String, Object>> dishParamsCaptor = org.mockito.ArgumentCaptor.forClass(Map.class);
        verify(orderService).statisticsDishSales(dishParamsCaptor.capture());
        Map<String, Object> capturedParams = dishParamsCaptor.getValue();
        assertEquals(7, capturedParams.get("shopId"));
        assertEquals(7, capturedParams.get("shop_id"));
    }

    @Test
    void dailyDetailFallbackDoesNotReportCreditSaleAsPaymentCollection() {
        when(dailyCloseService.generateZReport(eq(7), eq("2026-10-02")))
                .thenThrow(new IllegalStateException("z report unavailable"));

        Order credit = new Order();
        credit.setId(201);
        credit.setSett_amount(100.0d);
        credit.setPayment_method("挂账");
        Order cash = new Order();
        cash.setId(202);
        cash.setSett_amount(50.0d);
        cash.setPayment_method("现金");
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Arrays.asList(credit, cash));
        when(receivableService.summarizeWindow(any(), eq(7), any(), any()))
                .thenReturn(new ReceivableWindowSummary(10000L, 4000L, 0L, 0L, 6000L, 22L));

        R response = controller.daily("2026-10-02", null, null, null, true);

        Map<?, ?> report = (Map<?, ?>) response.get("report");
        List<?> paymentChannels = (List<?>) report.get("paymentChannels");
        double channelTotal = paymentChannels.stream()
                .map(Map.class::cast)
                .mapToDouble(row -> ((Number) row.get("amount")).doubleValue())
                .sum();
        assertEquals(50.0d, channelTotal);
        assertTrue(paymentChannels.stream().map(Map.class::cast)
                .noneMatch(row -> String.valueOf(row.get("channelLabel")).contains("挂账")));
        Map<?, ?> receivable = (Map<?, ?>) report.get("receivableSummary");
        assertEquals(10000L, receivable.get("chargedFen"));
        assertEquals(4000L, receivable.get("collectedFen"));
    }
}
