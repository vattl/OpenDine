package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.*;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.*;
import com.lanf.payment.service.OrderLedgerConsistencyService;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.security.JwtTokenService;
import com.lanf.service.*;
import com.lanf.service.impl.DailyCloseServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminDailyContextApiTest {

    private DailyCloseServiceImpl service;
    private DailyCloseSnapshotMapper snapshotMapper;
    private DailyAdjustmentMapper adjustmentMapper;
    private IDailyStatService dailyStatService;
    private IOrderService orderService;
    private IPaymentService paymentService;
    private IShopService shopService;
    private DrawerSessionMapper drawerSessionMapper;
    private CashMovementMapper cashMovementMapper;
    private PaymentLedgerMapper paymentLedgerMapper;
    private IAdminService adminService;
    private JwtTokenService jwtTokenService;
    private IMemberRechargeService memberRechargeService;
    private ReceivableService receivableService;
    private OrderLedgerConsistencyService consistencyService;

    private Shop shop;

    @BeforeEach
    void setUp() {
        service = new DailyCloseServiceImpl();
        snapshotMapper = mock(DailyCloseSnapshotMapper.class);
        adjustmentMapper = mock(DailyAdjustmentMapper.class);
        dailyStatService = mock(IDailyStatService.class);
        orderService = mock(IOrderService.class);
        paymentService = mock(IPaymentService.class);
        shopService = mock(IShopService.class);
        drawerSessionMapper = mock(DrawerSessionMapper.class);
        cashMovementMapper = mock(CashMovementMapper.class);
        paymentLedgerMapper = mock(PaymentLedgerMapper.class);
        adminService = mock(IAdminService.class);
        jwtTokenService = new JwtTokenService("0123456789abcdef0123456789abcdef", "");
        memberRechargeService = mock(IMemberRechargeService.class);
        receivableService = mock(ReceivableService.class);
        consistencyService = mock(OrderLedgerConsistencyService.class);

        ReflectionTestUtils.setField(service, "snapshotMapper", snapshotMapper);
        ReflectionTestUtils.setField(service, "adjustmentMapper", adjustmentMapper);
        ReflectionTestUtils.setField(service, "dailyStatService", dailyStatService);
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "paymentService", paymentService);
        ReflectionTestUtils.setField(service, "shopService", shopService);
        ReflectionTestUtils.setField(service, "drawerSessionMapper", drawerSessionMapper);
        ReflectionTestUtils.setField(service, "cashMovementMapper", cashMovementMapper);
        ReflectionTestUtils.setField(service, "paymentLedgerMapper", paymentLedgerMapper);
        ReflectionTestUtils.setField(service, "adminService", adminService);
        ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(service, "jwtTokenService", jwtTokenService);
        ReflectionTestUtils.setField(service, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(service, "receivableService", receivableService);
        ReflectionTestUtils.setField(service, "orderLedgerConsistencyService", consistencyService);

        when(memberRechargeService.summarizeSuccessfulByWindow(any(), any(), any()))
                .thenReturn(MemberRechargeSummary.empty());
        when(receivableService.summarizeWindow(any(), any(), any(), any()))
                .thenReturn(ReceivableWindowSummary.empty());
        when(consistencyService.audit(any())).thenReturn(Collections.emptyList());

        shop = new Shop();
        shop.setId(1);
        shop.setName("总店");
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);
        when(shopService.getOne(any(), anyBoolean())).thenReturn(shop);
    }

    @Test
    void getDailyContext_unclosed_returnsUnifiedPayloadWithSummaryAndChannels() {
        when(snapshotMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> ctx = service.getDailyContext(1, 10, "2026-10-24", 30);

        assertNotNull(ctx);
        assertEquals("2026-10-24", ctx.get("stat_date"));
        assertEquals(false, ctx.get("is_already_settled"));
        assertEquals(false, ctx.get("settled"));
        assertEquals(true, ctx.get("can_settle"));

        // summary
        assertTrue(ctx.containsKey("summary"));
        @SuppressWarnings("unchecked")
        Map<String, Object> summary = (Map<String, Object>) ctx.get("summary");
        assertEquals(0.0, summary.get("total_amount"));
        assertEquals(false, summary.get("settled"));

        // channels
        assertTrue(ctx.containsKey("channels"));
        assertTrue(ctx.containsKey("channel_details"));
        assertTrue(ctx.containsKey("income"));
        assertTrue(ctx.containsKey("deduction"));
        assertTrue(ctx.containsKey("blockers"));
        assertTrue(ctx.containsKey("warnings"));
        assertNotNull(ctx.get("precheck_token"));
    }

    @Test
    void getDailyContext_closed_returnsArchivedSnapshotAndChannels() {
        DailyCloseSnapshot snapshot = new DailyCloseSnapshot();
        snapshot.setId(100L);
        snapshot.setSnapshot_no("DSN20261024001");
        snapshot.setShop_id(1);
        snapshot.setBusiness_day("2026-10-24");
        snapshot.setState(DailyCloseSnapshot.STATE_CLOSED);
        snapshot.setNet_sales_fen(128000L);
        snapshot.setTotal_sales_fen(130000L);
        snapshot.setDiscount_amount_fen(2000L);
        snapshot.setRefund_amount_fen(0L);
        snapshot.setOrder_count(25);
        snapshot.setDrawer_session_count(2);
        snapshot.setTotal_cash_variance_fen(0);
        snapshot.setTotal_collections_fen(128000L);
        snapshot.setClosed_at(new Date());
        snapshot.setChannel_breakdown_json("[{\"channel\":\"wechat\",\"name\":\"微信支付\",\"net_amount_fen\":100000,\"success_count\":20},{\"channel\":\"cash\",\"name\":\"现金\",\"net_amount_fen\":28000,\"success_count\":5}]");

        when(snapshotMapper.selectOne(any())).thenReturn(snapshot);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(snapshot));
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> ctx = service.getDailyContext(1, 10, "2026-10-24", 30);

        assertNotNull(ctx);
        assertEquals(true, ctx.get("is_already_settled"));
        assertEquals(true, ctx.get("settled"));
        assertEquals("DSN20261024001", ctx.get("existing_snapshot_no"));

        @SuppressWarnings("unchecked")
        Map<String, Object> summary = (Map<String, Object>) ctx.get("summary");
        assertEquals(1280.0, summary.get("total_amount"));
        assertEquals(1300.0, summary.get("gross_sales"));
        assertEquals(20.0, summary.get("discount_amount"));
        assertEquals(true, summary.get("settled"));

        @SuppressWarnings("unchecked")
        Map<String, Double> channels = (Map<String, Double>) ctx.get("channels");
        assertEquals(1000.0, channels.get("微信支付"));
        assertEquals(280.0, channels.get("现金"));
        assertEquals(true, ctx.get("can_reopen"));
    }

    @Test
    void adminDailyController_acceptsBothStatDateAndDateAliases() {
        AdminDailyController controller = new AdminDailyController();
        ReflectionTestUtils.setField(controller, "dailyCloseService", service);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(controller, "request", request);

        when(snapshotMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        // 1. With stat_date
        R r1 = controller.getDailyContext("2026-10-24", null, 30);
        assertEquals(0, r1.get("code"));
        assertEquals("2026-10-24", r1.get("stat_date"));

        // 2. With date
        R r2 = controller.getDailyContext(null, "2026-10-24", 30);
        assertEquals(0, r2.get("code"));
        assertEquals("2026-10-24", r2.get("stat_date"));
    }

    @Test
    void getDailyContext_closed_withStructuredChannelJson_serializesSuccessfully() throws Exception {
        DailyCloseSnapshot snapshot = new DailyCloseSnapshot();
        snapshot.setId(100L);
        snapshot.setSnapshot_no("DSN20261010001");
        snapshot.setShop_id(1);
        snapshot.setBusiness_day("2026-10-10");
        snapshot.setState(DailyCloseSnapshot.STATE_CLOSED);
        snapshot.setNet_sales_fen(128000L);
        snapshot.setTotal_sales_fen(130000L);
        snapshot.setClosed_at(new Date());
        // Real production structure saved by settle(): code, label, success_count, net_amount_fen
        snapshot.setChannel_breakdown_json("[{\"code\":\"wechat\",\"label\":\"微信支付\",\"net_amount_fen\":100000,\"success_count\":20},{\"code\":\"cash\",\"label\":\"现金\",\"net_amount_fen\":28000,\"success_count\":5}]");

        when(snapshotMapper.selectOne(any())).thenReturn(snapshot);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(snapshot));
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> ctx = service.getDailyContext(1, 10, "2026-10-10", 30);
        // Verify JSON serialization doesn't throw Null key exception
        String json = new ObjectMapper().writeValueAsString(ctx);
        assertNotNull(json);
    }

    @Test
    void getDailyContext_unclosed_withLedgerChannels_serializesSuccessfully() throws Exception {
        when(snapshotMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);

        PaymentLedger ledger = new PaymentLedger();
        ledger.setId(1L);
        ledger.setShop_id(1);
        ledger.setChannel("wechat");
        ledger.setAmount_fen(8800);
        ledger.setStatus(PaymentLedger.STATUS_SUCCEEDED);
        ledger.setEntry_type(PaymentLedger.ENTRY_TYPE_PAYMENT);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.singletonList(ledger));
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> ctx = service.getDailyContext(1, 10, "2026-10-24", 30);
        String json = new ObjectMapper().writeValueAsString(ctx);
        assertNotNull(json);

        @SuppressWarnings("unchecked")
        Map<String, Double> channels = (Map<String, Double>) ctx.get("channels");
        assertTrue(channels.containsKey("微信支付"));
        assertEquals(88.0, channels.get("微信支付"));
        assertFalse(channels.containsKey(null));
    }

    @Test
    @SuppressWarnings("unchecked")
    void getDailyContext_unclosed_includesCreditSaleInChannelsAndChannelDetails() {
        when(snapshotMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Order creditOrder = new Order();
        creditOrder.setOrder_no("ORD-CREDIT-001");
        creditOrder.setTransac_status("success");
        creditOrder.setPayment_method("挂账");
        creditOrder.setSett_amount(88.0d);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(creditOrder));
        when(orderService.count(any())).thenReturn(1);

        Map<String, Object> ctx = service.getDailyContext(1, 10, "2026-10-24", 30);

        assertNotNull(ctx);
        Map<String, Double> channels = (Map<String, Double>) ctx.get("channels");
        assertNotNull(channels);
        assertEquals(88.0, channels.get("挂账"));

        List<Map<String, Object>> details = (List<Map<String, Object>>) ctx.get("channel_details");
        assertNotNull(details);
        boolean foundReceivable = details.stream().anyMatch(d -> "receivable".equals(d.get("channel")) && "挂账".equals(d.get("name")));
        assertTrue(foundReceivable);
    }

    @Test
    @SuppressWarnings("unchecked")
    void getDailyContext_closed_backfillsReceivableChannelIfHistoricalSnapshotMissingChannel() {
        DailyCloseSnapshot snapshot = new DailyCloseSnapshot();
        snapshot.setId(101L);
        snapshot.setSnapshot_no("DSN20261024002");
        snapshot.setShop_id(1);
        snapshot.setBusiness_day("2026-10-24");
        snapshot.setState(DailyCloseSnapshot.STATE_CLOSED);
        snapshot.setNet_sales_fen(150000L);
        snapshot.setTotal_sales_fen(150000L);
        snapshot.setReceivable_charged_fen(5000L);
        snapshot.setOrder_count(10);
        snapshot.setDrawer_session_count(1);
        snapshot.setTotal_cash_variance_fen(0);
        snapshot.setTotal_collections_fen(100000L);
        snapshot.setClosed_at(new Date());
        snapshot.setChannel_breakdown_json("[{\"channel\":\"wechat\",\"name\":\"微信支付\",\"net_amount_fen\":100000,\"success_count\":8}]");

        when(snapshotMapper.selectOne(any())).thenReturn(snapshot);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(snapshot));
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> ctx = service.getDailyContext(1, 10, "2026-10-24", 30);

        assertNotNull(ctx);
        Map<String, Double> channels = (Map<String, Double>) ctx.get("channels");
        assertNotNull(channels);
        assertEquals(50.0, channels.get("挂账"));

        List<Map<String, Object>> details = (List<Map<String, Object>>) ctx.get("channel_details");
        assertNotNull(details);
        boolean foundReceivable = details.stream().anyMatch(d -> "receivable".equals(d.get("channel")) && "挂账".equals(d.get("name")));
        assertTrue(foundReceivable);
    }
}
