package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.*;
import com.lanf.mapper.*;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.payment.service.OrderLedgerConsistencyService;
import com.lanf.service.impl.DailyCloseServiceImpl;
import com.lanf.security.JwtTokenService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DailyCloseServiceTest {

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
        shop.setName("测试总店");
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);
        when(shopService.getOne(any(), anyBoolean())).thenReturn(shop);
    }

    @Test
    void precheck_whenOpenDrawerSessionExists_returnsBlocker() {
        DrawerSession openSession = new DrawerSession();
        openSession.setId(10L);
        openSession.setState(DrawerSession.STATE_OPEN);
        openSession.setTerminal_id("POS-01");
        openSession.setDrawer_code("D01");

        when(drawerSessionMapper.selectList(any())).thenReturn(
                Collections.singletonList(openSession),
                Collections.emptyList(),
                Collections.emptyList()
        );
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.precheck(1, "2026-10-03");

        assertFalse((Boolean) result.get("can_settle"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) result.get("blockers");
        assertEquals(1, blockers.size());
        assertEquals("OPEN_DRAWER_SESSIONS", blockers.get(0).get("code"));
        assertNull(result.get("precheck_token"));
        assertNull(result.get("precheck_expires_at"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Wrapper<DrawerSession>> drawerCaptor = ArgumentCaptor.forClass(Wrapper.class);
        verify(drawerSessionMapper, atLeastOnce()).selectList(drawerCaptor.capture());
        assertTrue(drawerCaptor.getAllValues().get(0).getCustomSqlSegment().contains("business_day"),
                "Open drawers from a later business day must not block a historical close");
    }

    @Test
    void precheck_withoutDate_selectsEarliestGapInsteadOfCurrentBusinessDay() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        LocalDate first = current.minusDays(3);
        LocalDate missing = current.minusDays(2);
        when(snapshotMapper.selectList(any())).thenReturn(Arrays.asList(
                closedSnapshot(first),
                closedSnapshot(current.minusDays(1))
        ));
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.precheck(1, null);

        assertEquals(missing.toString(), result.get("stat_date"));
        assertEquals(missing.toString(), result.get("next_close_business_day"));
        assertEquals(current.toString(), result.get("current_business_day"));
        assertEquals(Boolean.TRUE, result.get("has_previous_unclosed_day"));
        assertEquals(2, result.get("pending_day_count"));
    }

    @Test
    void precheck_whenLaterDayRequested_rejectsOutOfSequence() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        LocalDate expected = current.minusDays(1);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(
                closedSnapshot(current.minusDays(2))
        ));

        ApiException ex = assertThrows(ApiException.class,
                () -> service.precheck(1, current.toString()));

        assertEquals(409, ex.getHttpStatus());
        assertEquals("DAILY_CLOSE_OUT_OF_SEQUENCE", ex.getErrorCode());
        @SuppressWarnings("unchecked")
        Map<String, Object> details = (Map<String, Object>) ex.getData();
        assertEquals(expected.toString(), details.get("expected_business_day"));
        assertEquals(current.toString(), details.get("requested_business_day"));
    }

    @Test
    void precheck_whenOpenOrdersExist_returnsBlocker() {
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        Order o1 = new Order();
        o1.setId(101);
        o1.setOrder_no("O1");
        o1.setTransac_status("unsettled");
        when(orderService.count(any())).thenReturn(1);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(o1), Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.precheck(1, "2026-10-03");

        assertFalse((Boolean) result.get("can_settle"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) result.get("blockers");
        assertEquals(1, blockers.size());
        assertEquals("OPEN_ORDERS", blockers.get(0).get("code"));
    }

    @Test
    void precheck_whenClean_canSettleIsTrue() {
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.precheck(1, "2026-10-03");

        assertTrue((Boolean) result.get("can_settle"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) result.get("blockers");
        assertTrue(blockers.isEmpty());
        assertNotNull(result.get("precheck_token"));
        assertNotNull(result.get("precheck_expires_at"));

        @SuppressWarnings("unchecked")
        Map<String, Object> preview = (Map<String, Object>) result.get("preview");
        assertTrue(preview.containsKey("gross_sales_fen"));
        assertTrue(preview.containsKey("discount_amount_fen"));
        assertTrue(preview.containsKey("refund_amount_fen"));
        assertTrue(preview.containsKey("net_sales_fen"));
        assertTrue(preview.containsKey("cash_variance_fen"));
        assertTrue(preview.containsKey("channels"));
        assertTrue(preview.containsKey("member_recharge_summary"));
        assertTrue(preview.containsKey("total_collections_fen"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Wrapper<PaymentLedger>> ledgerCaptor = ArgumentCaptor.forClass(Wrapper.class);
        verify(paymentLedgerMapper).selectCount(ledgerCaptor.capture());
        String sql = ledgerCaptor.getValue().getCustomSqlSegment();
        assertTrue(sql.contains("occurred_at"), "Must query occurred_at column");
        assertFalse(sql.contains("transac_time"), "Must not query nonexistent transac_time column");

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Wrapper<Order>> orderCaptor = ArgumentCaptor.forClass(Wrapper.class);
        verify(orderService).count(orderCaptor.capture());
        String orderSql = orderCaptor.getValue().getCustomSqlSegment();
        assertTrue(orderSql.contains("transac_status"), "Must query transac_status column");
        assertFalse(orderSql.contains("order_status"), "Must not query nonexistent order_status column");
        assertTrue(orderSql.contains("merchantId"), "Must query merchantId column");
    }

    @Test
    void precheck_whenPaidOrderAndLedgerMismatch_blocksDailyCloseAndToken() {
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        Order order = new Order();
        order.setOrder_no("ORD-MISMATCH");
        order.setTransac_status("success");
        order.setSett_amount(100d);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));
        when(paymentService.list(any())).thenReturn(Collections.emptyList());
        OrderLedgerConsistencyService.Issue issue = new OrderLedgerConsistencyService.Issue(
                "ORD-MISMATCH",
                Collections.singletonMap(PaymentLedger.CHANNEL_CASH, 10000),
                Collections.emptyMap());
        when(consistencyService.audit(any())).thenReturn(Collections.singletonList(issue));

        Map<String, Object> result = service.precheck(1, "2026-10-03");

        assertFalse((Boolean) result.get("can_settle"));
        assertNull(result.get("precheck_token"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) result.get("blockers");
        Map<String, Object> blocker = blockers.stream()
                .filter(b -> "ORDER_LEDGER_MISMATCH".equals(b.get("code")))
                .findFirst().orElseThrow(AssertionError::new);
        @SuppressWarnings("unchecked")
        Map<String, Integer> reasonSummary = (Map<String, Integer>) blocker.get("reason_summary");
        assertEquals(Integer.valueOf(1), reasonSummary.get("LEDGER_MISSING"));
        assertEquals(Integer.valueOf(1), reasonSummary.get("TOTAL_AMOUNT_SHORT"));
        assertEquals(Integer.valueOf(1), reasonSummary.get("CHANNEL_LEDGER_MISSING"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> details = (List<Map<String, Object>>) blocker.get("details");
        assertEquals("ORD-MISMATCH", details.get(0).get("order_no"));
        assertTrue(String.valueOf(details.get(0).get("reason")).contains("缺少成功资金流水"));
        assertEquals(-10000, details.get(0).get("difference_fen"));
    }

    @Test
    void precheck_countsCreditSaleAsSalesButOnlyActualCollectionAsCollections() {
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        Order creditSale = new Order();
        creditSale.setOrder_no("AR-ORDER-1");
        creditSale.setTransac_status("success");
        creditSale.setPayment_method("挂账");
        creditSale.setSett_amount(100.0d);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(creditSale));
        when(paymentService.list(any())).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(receivableService.summarizeWindow(any(), eq(1), any(), any()))
                .thenReturn(new ReceivableWindowSummary(10_000L, 4_000L, 0L, 0L, 6_000L, 9L));

        Map<String, Object> result = service.precheck(1, "2026-10-03");
        @SuppressWarnings("unchecked")
        Map<String, Object> preview = (Map<String, Object>) result.get("preview");
        @SuppressWarnings("unchecked")
        Map<String, Object> receivable = (Map<String, Object>) preview.get("receivable_summary");

        assertEquals(10_000L, preview.get("net_sales_fen"));
        assertEquals(4_000L, preview.get("total_collections_fen"));
        assertEquals(10_000L, receivable.get("charged_fen"));
        assertEquals(4_000L, receivable.get("collected_fen"));
        assertEquals(6_000L, receivable.get("outstanding_fen"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> channels = (List<Map<String, Object>>) preview.get("channels");
        assertNotNull(channels);
        assertEquals(1, channels.size());
        assertEquals("receivable", channels.get(0).get("code"));
        assertEquals("挂账", channels.get(0).get("label"));
        assertEquals(10_000L, channels.get(0).get("net_amount_fen"));
        assertEquals(1, channels.get(0).get("success_count"));
    }

    @Test
    void printableReportSeparatesNetSalesFromCollectionsAndShowsReceivables() {
        Map<String, Object> report = new LinkedHashMap<>();
        Map<String, Object> sales = new LinkedHashMap<>();
        sales.put("total_sales", 100.0d);
        sales.put("discount_amount", 0.0d);
        sales.put("refund_amount", 0.0d);
        sales.put("net_sales", 100.0d);
        sales.put("order_count", 1);
        report.put("sales_summary", sales);
        report.put("member_recharge_summary", MemberRechargeSummary.empty().toMap());
        report.put("total_collections_fen", 4000L);
        report.put("receivable_summary", new ReceivableWindowSummary(
                10000L, 4000L, 500L, 1000L, 4500L, 9L).toMap());

        String text = ReflectionTestUtils.invokeMethod(service, "buildPrintableZReportText", report);

        assertNotNull(text);
        assertTrue(text.contains("净销售额"));
        assertTrue(text.contains("实际收款合计"));
        assertTrue(text.contains("新增挂账"));
        assertTrue(text.contains("应收回款"));
        assertTrue(text.contains("坏账核销"));
        assertTrue(text.contains("挂账撤销"));
        assertTrue(text.contains("期末应收余额"));
        assertFalse(text.contains("净营业实收"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void closedSnapshotReceivableSummaryPreservesReversedAmount() {
        DailyCloseSnapshot snapshot = new DailyCloseSnapshot();
        ReflectionTestUtils.setField(snapshot, "receivable_reversed_fen", 1250L);

        Map<String, Object> summary = ReflectionTestUtils.invokeMethod(
                DailyCloseServiceImpl.class, "snapshotReceivableSummary", snapshot);

        assertNotNull(summary);
        assertEquals(1250L, summary.get("reversed_fen"));
    }

    @Test
    void precheck_splitsQrChannelsUsingOrderPaymentMethod() {
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        Order wx = new Order();
        wx.setOrder_no("ORD-WX-QR");
        wx.setPayment_method("微信收款码");
        wx.setSett_amount(80d);
        Order ali = new Order();
        ali.setOrder_no("ORD-ALI-QR");
        ali.setPayment_method("支付宝收款码自动");
        ali.setSett_amount(90d);
        when(orderService.list(any(Wrapper.class))).thenReturn(Arrays.asList(wx, ali));
        when(paymentService.list(any())).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectList(any())).thenReturn(Arrays.asList(
                PaymentLedger.builder().channel(PaymentLedger.CHANNEL_WECHAT)
                        .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT).amount_fen(8000)
                        .order_no("ORD-WX-QR").build(),
                PaymentLedger.builder().channel(PaymentLedger.CHANNEL_ALIPAY)
                        .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT).amount_fen(9000)
                        .order_no("ORD-ALI-QR").build()));

        Map<String, Object> result = service.precheck(1, "2026-10-03");

        @SuppressWarnings("unchecked")
        Map<String, Object> preview = (Map<String, Object>) result.get("preview");
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> channels = (List<Map<String, Object>>) preview.get("channels");
        assertEquals("wechat_qr", channels.get(0).get("code"));
        assertEquals("微信收款码", channels.get(0).get("label"));
        assertEquals("alipay_qr", channels.get(1).get("code"));
        assertEquals("支付宝收款码", channels.get(1).get("label"));
    }

    @Test
    void settle_withoutPrecheckToken_isRejectedWithStableConflictCode() {
        when(snapshotMapper.selectOne(any())).thenReturn(null);

        ApiException ex = assertThrows(ApiException.class, () ->
                service.settle(1, 1, "2026-10-03", null, null, false)
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRECHECK_EXPIRED", ex.getErrorCode());
    }

    @Test
    void settle_evenWithForce_rejectsLaterBusinessDayWhenEarlierDayIsPending() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        LocalDate expected = current.minusDays(1);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(
                closedSnapshot(current.minusDays(2))
        ));

        ApiException ex = assertThrows(ApiException.class, () ->
                service.settle(1, 1, current.toString(), "unused", null, true)
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("DAILY_CLOSE_OUT_OF_SEQUENCE", ex.getErrorCode());
        @SuppressWarnings("unchecked")
        Map<String, Object> details = (Map<String, Object>) ex.getData();
        assertEquals(expected.toString(), details.get("expected_business_day"));
        verify(snapshotMapper, never()).insert(any());
        verify(snapshotMapper, never()).updateById(any());
    }

    @Test
    void settle_whenAlreadySettled_returnsIdempotentSnapshot() {
        DailyCloseSnapshot existingSnapshot = DailyCloseSnapshot.builder()
                .id(100L)
                .snapshot_no("DSN2026100300019999")
                .shop_id(1)
                .business_day("2026-10-03")
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .net_sales_fen(50000L)
                .build();
        when(snapshotMapper.selectOne(any())).thenReturn(existingSnapshot);

        Map<String, Object> result = service.settle(1, 1, "2026-10-03", validPrecheckToken(), null, false);

        assertTrue((Boolean) result.get("idempotent"));
        assertEquals(existingSnapshot, result.get("snapshot"));
        verify(snapshotMapper, never()).insert(any());
    }

    @Test
    void settle_whenAlreadySettledWithDifferentKey_returnsStableConflict() {
        DailyCloseSnapshot existingSnapshot = DailyCloseSnapshot.builder()
                .id(100L)
                .snapshot_no("DSN2026100300019999")
                .shop_id(1)
                .business_day("2026-10-03")
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .settle_idempotency_key("close-request-a")
                .build();
        when(snapshotMapper.selectOne(any())).thenReturn(existingSnapshot);

        ApiException ex = assertThrows(ApiException.class, () ->
                service.settle(1, 1, "2026-10-03", validPrecheckToken(), null, false, "close-request-b")
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("DAILY_ALREADY_SETTLED", ex.getErrorCode());
    }

    @Test
    void settle_whenSourceWatermarkChanged_returnsStableConflict() {
        when(snapshotMapper.selectOne(any())).thenReturn(null);
        when(paymentLedgerMapper.selectOne(any())).thenReturn(PaymentLedger.builder().id(9L).build());

        ApiException ex = assertThrows(ApiException.class, () ->
                service.settle(1, 1, "2026-10-03", validPrecheckToken(), null, false, "close-request-a")
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("WATERMARK_CHANGED", ex.getErrorCode());
    }

    @Test
    void settle_success_writesSnapshotAndSyncsDailyStat() {
        when(snapshotMapper.selectOne(any())).thenReturn(null);
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);

        Order o1 = new Order();
        o1.setId(101);
        o1.setSett_amount(170.0);
        o1.setDiscount_amount(20.0);
        o1.setRefund_amount(0.0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(o1));

        Payment p1 = new Payment();
        p1.setPayment_method("cash");
        p1.setAmount(BigDecimal.valueOf(150.0));
        when(paymentService.list(any())).thenReturn(Collections.singletonList(p1));
        when(memberRechargeService.summarizeSuccessfulByWindow(any(), any(), any()))
                .thenReturn(new MemberRechargeSummary(2, 10000, 1000));

        when(snapshotMapper.insert(any(DailyCloseSnapshot.class))).thenAnswer(inv -> {
            DailyCloseSnapshot s = inv.getArgument(0);
            s.setId(100L);
            return 1;
        });

        Map<String, Object> result = service.settle(1, 1, "2026-10-03", validPrecheckToken(), null, false);

        assertFalse((Boolean) result.get("idempotent"));
        DailyCloseSnapshot snapshot = (DailyCloseSnapshot) result.get("snapshot");
        assertNotNull(snapshot);
        assertEquals(15000L, snapshot.getNet_sales_fen());
        assertEquals(17000L, snapshot.getTotal_sales_fen());
        assertEquals(10000L, snapshot.getMember_recharge_fen());
        assertEquals(1000L, snapshot.getMember_recharge_gift_fen());
        assertEquals(2, snapshot.getMember_recharge_count());
        assertNotNull(snapshot.getSnapshot_hash());

        verify(dailyStatService).saveOrUpdate(any(DailyStat.class));
    }

    @Test
    void settle_whenReopened_reusesSnapshotRowInsteadOfViolatingUniqueBusinessDay() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        DailyCloseSnapshot reopened = DailyCloseSnapshot.builder()
                .id(100L)
                .snapshot_no("DSN-ORIGINAL")
                .shop_id(1)
                .business_day(current.toString())
                .state(DailyCloseSnapshot.STATE_REOPENED)
                .reopen_reason("补录漏单")
                .build();
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(reopened));
        when(snapshotMapper.selectOne(any())).thenReturn(null);
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.settle(
                1, 1, current.toString(), validPrecheckToken(current.toString()), null, false);

        DailyCloseSnapshot snapshot = (DailyCloseSnapshot) result.get("snapshot");
        assertEquals(100L, snapshot.getId());
        assertEquals("DSN-ORIGINAL", snapshot.getSnapshot_no());
        assertEquals(DailyCloseSnapshot.STATE_CLOSED, snapshot.getState());
        assertEquals("补录漏单", snapshot.getReopen_reason());
        verify(snapshotMapper).updateById(snapshot);
        verify(snapshotMapper, never()).insert(any());
    }

    @Test
    void settle_whenRechargeWatermarkChanged_returnsStableConflict() {
        when(snapshotMapper.selectOne(any())).thenReturn(null);
        // A pending row may become success without changing its id. The success-count
        // watermark must still invalidate the precheck token.
        when(memberRechargeService.getOne(any(), anyBoolean())).thenReturn(null);
        when(memberRechargeService.count(any())).thenReturn(1);

        ApiException ex = assertThrows(ApiException.class, () ->
                service.settle(1, 1, "2026-10-03", validPrecheckToken(), null, false, "close-request-a")
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("WATERMARK_CHANGED", ex.getErrorCode());
    }

    @Test
    void recordAdjustment_success_createsAdjustmentRecord() {
        DailyCloseSnapshot snapshot = DailyCloseSnapshot.builder()
                .id(100L)
                .shop_id(1)
                .business_day("2026-10-03")
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .build();
        when(snapshotMapper.selectById(100L)).thenReturn(snapshot);
        when(adjustmentMapper.insert(any(DailyAdjustment.class))).thenReturn(1);

        DailyAdjustment adj = service.recordAdjustment(
                1, 1, 100L, DailyAdjustment.TYPE_POST_CLOSE_REFUND, -3000, 101L, 201L, "客户跨日补退款", 1
        );

        assertNotNull(adj);
        assertEquals(100L, adj.getSnapshot_id());
        assertEquals(-3000, adj.getAmount_fen());
        verify(adjustmentMapper).insert(any(DailyAdjustment.class));
    }

    @Test
    void reopen_success_updatesStateToReopened() {
        DailyCloseSnapshot snapshot = DailyCloseSnapshot.builder()
                .id(100L)
                .shop_id(1)
                .business_day("2026-10-03")
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .build();
        when(snapshotMapper.selectOne(any())).thenReturn(snapshot);
        when(adminService.getById(1)).thenReturn(null); // password check passes if admin null or match

        Map<String, Object> result = service.reopen(1, 1, "2026-10-03", "123456", "补打漏单重结");

        assertTrue((Boolean) result.get("reopened"));
        assertEquals(DailyCloseSnapshot.STATE_REOPENED, snapshot.getState());
        assertEquals("补打漏单重结", snapshot.getReopen_reason());
        verify(snapshotMapper).updateById(snapshot);
    }

    @Test
    void reopen_whenLaterClosedDayExists_rejectsSequenceHole() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        DailyCloseSnapshot requested = closedSnapshot(current.minusDays(1));
        requested.setId(100L);
        when(snapshotMapper.selectOne(any())).thenReturn(requested);
        when(snapshotMapper.selectList(any())).thenReturn(Arrays.asList(
                requested,
                closedSnapshot(current)
        ));
        when(adminService.getById(1)).thenReturn(null);

        ApiException ex = assertThrows(ApiException.class, () ->
                service.reopen(1, 1, requested.getBusiness_day(), "123456", "补录")
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("DAILY_REOPEN_OUT_OF_SEQUENCE", ex.getErrorCode());
        verify(snapshotMapper, never()).updateById(requested);
    }

    @Test
    void testGenerateZReport_handlesDatetimeStringWithTimestamp() {
        when(shopService.getById(1)).thenReturn(shop);
        DailyCloseSnapshot snapshot = DailyCloseSnapshot.builder()
                .id(100L)
                .snapshot_no("SNAP20261003001")
                .shop_id(1)
                .business_day("2026-10-03")
                .total_sales_fen(10000L)
                .discount_amount_fen(1000L)
                .refund_amount_fen(0L)
                .net_sales_fen(9000L)
                .order_count(5)
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .channel_breakdown_json("{\"wxpay\":90.0}")
                .drawer_summary_json("{\"expected\":90.0}")
                .total_cash_variance_fen(0)
                .snapshot_hash("abc1234567890def1234567890abcdef")
                .build();
        when(snapshotMapper.selectOne(any())).thenReturn(snapshot);
        when(adjustmentMapper.selectList(any())).thenReturn(Collections.emptyList());

        // Test with "2026-10-03 00:00:00" containing space and time
        Map<String, Object> reportWithTime = service.generateZReport(1, "2026-10-03 00:00:00");
        assertNotNull(reportWithTime);
        assertEquals("2026-10-03", reportWithTime.get("business_day"));
        assertEquals("Z_REPORT", reportWithTime.get("report_type"));
        @SuppressWarnings("unchecked")
        Map<String, Long> watermarks = (Map<String, Long>) reportWithTime.get("watermarks");
        assertEquals(0L, watermarks.get("payment_ledger_id"));
        assertEquals(0L, watermarks.get("cash_event_id"));
        assertEquals(0L, watermarks.get("order_id"));

        // Test with ISO "2026-10-03T00:00:00"
        Map<String, Object> reportWithT = service.generateZReport(1, "2026-10-03T00:00:00");
        assertNotNull(reportWithT);
        assertEquals("2026-10-03", reportWithT.get("business_day"));
    }

    @Test
    void listZReports_withNullDateRange_succeedsWithoutNpe() {
        Admin admin = new Admin();
        admin.setId(1);
        admin.setRealName("张晓明");
        admin.setJobTitle("店长");
        admin.setWorkNo("EMP1001");
        when(adminService.getById(1)).thenReturn(admin);

        DailyCloseSnapshot s = DailyCloseSnapshot.builder()
                .id(101L)
                .snapshot_no("DSN20261003001")
                .shop_id(1)
                .business_day("2026-10-03")
                .net_sales_fen(50000L)
                .order_count(25)
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .operator_id(1)
                .closed_at(new Date())
                .snapshot_hash("hash123")
                .cutoff_ledger_id(10L)
                .cutoff_movement_id(20L)
                .cutoff_order_id(30L)
                .build();
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(s));

        Map<String, Object> result = service.listZReports(1, "2026-10-03", "2026-10-03", null, 100);
        assertNotNull(result);
        assertTrue(result.containsKey("items"));
        assertFalse((Boolean) result.get("has_more"));
        assertNull(result.get("next_cursor"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) result.get("items");
        assertEquals(1, items.size());
        Map<String, Object> item = items.get(0);
        assertEquals(101L, item.get("id"));
        assertEquals("DSN20261003001", item.get("snapshot_no"));
        assertEquals("2026-10-03", item.get("business_day"));
        assertEquals(50000L, item.get("net_sales_fen"));
        assertEquals(25, item.get("order_count"));
        assertEquals(1, item.get("operator_id"));
        assertEquals("张晓明", item.get("operator_name"));

        @SuppressWarnings("unchecked")
        Map<String, Long> watermarks = (Map<String, Long>) item.get("watermarks");
        assertEquals(10L, watermarks.get("payment_ledger_id"));
        assertEquals(20L, watermarks.get("cash_event_id"));
        assertEquals(30L, watermarks.get("order_id"));
    }

    @Test
    void listZReports_returnsContinuousBusinessDaysWithCloseState() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        LocalDate first = current.minusDays(2);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(closedSnapshot(first)));

        Map<String, Object> result = service.listZReports(1, null, null, null, 10);

        assertEquals(current.toString(), result.get("current_business_day"));
        assertEquals(current.minusDays(1).toString(), result.get("next_close_business_day"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) result.get("items");
        assertEquals(3, items.size());
        assertEquals(current.toString(), items.get(0).get("business_day"));
        assertEquals("PENDING", items.get(0).get("close_state"));
        assertEquals(Boolean.FALSE, items.get(0).get("can_close"));
        assertEquals(current.minusDays(1).toString(), items.get(1).get("business_day"));
        assertEquals("PENDING", items.get(1).get("close_state"));
        assertEquals(Boolean.TRUE, items.get(1).get("can_close"));
        assertEquals(first.toString(), items.get(2).get("business_day"));
        assertEquals("CLOSED", items.get(2).get("close_state"));
        assertEquals(Boolean.FALSE, items.get(2).get("can_close"));
        assertFalse((Boolean) result.get("has_more"));
    }

    @Test
    void listZReports_marksReopenedDayAsOnlyActionableDay() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        DailyCloseSnapshot reopened = closedSnapshot(current.minusDays(1));
        reopened.setState(DailyCloseSnapshot.STATE_REOPENED);
        when(snapshotMapper.selectList(any())).thenReturn(Arrays.asList(
                closedSnapshot(current.minusDays(2)), reopened));

        Map<String, Object> result = service.listZReports(1, null, null, null, 10);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) result.get("items");
        assertEquals("PENDING", items.get(0).get("close_state"));
        assertEquals(Boolean.FALSE, items.get(0).get("can_close"));
        assertEquals("REOPENED", items.get(1).get("close_state"));
        assertEquals(Boolean.TRUE, items.get(1).get("can_close"));
        assertEquals(Boolean.TRUE, items.get(1).get("is_next_close_business_day"));
    }

    @Test
    void listZReports_usesExclusiveBusinessDayCursorWithoutGaps() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        LocalDate first = current.minusDays(4);
        when(snapshotMapper.selectList(any())).thenReturn(Collections.singletonList(closedSnapshot(first)));

        Map<String, Object> firstPage = service.listZReports(1, null, null, null, 2);
        assertTrue((Boolean) firstPage.get("has_more"));
        Long cursor = (Long) firstPage.get("next_cursor");
        assertEquals(Long.valueOf(current.minusDays(1).format(java.time.format.DateTimeFormatter.BASIC_ISO_DATE)), cursor);

        Map<String, Object> secondPage = service.listZReports(1, null, null, cursor, 2);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) secondPage.get("items");
        assertEquals(current.minusDays(2).toString(), items.get(0).get("business_day"));
        assertEquals(current.minusDays(3).toString(), items.get(1).get("business_day"));
    }

    @Test
    void listZReports_acceptsLegacySnapshotIdCursorDuringMigration() {
        LocalDate current = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        DailyCloseSnapshot first = closedSnapshot(current.minusDays(4));
        DailyCloseSnapshot legacyCursorSnapshot = closedSnapshot(current.minusDays(2));
        legacyCursorSnapshot.setId(404L);
        when(snapshotMapper.selectList(any())).thenReturn(Arrays.asList(first, legacyCursorSnapshot));
        when(snapshotMapper.selectById(404L)).thenReturn(legacyCursorSnapshot);

        Map<String, Object> result = service.listZReports(1, null, null, 404L, 10);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) result.get("items");
        assertEquals(2, items.size());
        assertEquals(current.minusDays(3).toString(), items.get(0).get("business_day"));
        assertEquals(current.minusDays(4).toString(), items.get(1).get("business_day"));
    }

    private String validPrecheckToken() {
        return validPrecheckToken("2026-10-03");
    }

    private String validPrecheckToken(String businessDay) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("shop_id", 1);
        claims.put("business_day", businessDay);
        claims.put("admin_id", 1);
        claims.put("payment_ledger_id", 0L);
        claims.put("cash_event_id", 0L);
        claims.put("order_id", 0L);
        claims.put("member_recharge_id", 0L);
        claims.put("member_recharge_success_count", 0L);
        return jwtTokenService.createToken(UUID.randomUUID().toString(), "daily-precheck", 300_000L, claims);
    }

    private DailyCloseSnapshot closedSnapshot(LocalDate day) {
        return DailyCloseSnapshot.builder()
                .shop_id(1)
                .business_day(day.toString())
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .build();
    }

    @Test
    void precheck_whenInBusinessHours_blocksSettleWithInBusinessHoursBlocker() {
        shop.setOpen_time("10:00");
        shop.setClose_time("22:00");
        shop.setSettle_time("04:00");

        // 模拟当前时间为 14:00（营业时段内）
        java.time.Instant simulatedNow = LocalDateTime.of(2026, 10, 29, 14, 0, 0)
                .atZone(java.time.ZoneId.of("Asia/Shanghai")).toInstant();
        service.setClock(java.time.Clock.fixed(simulatedNow, java.time.ZoneId.of("Asia/Shanghai")));

        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.precheck(1, "2026-10-29");

        assertFalse((Boolean) result.get("can_settle"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) result.get("blockers");
        assertTrue(blockers.stream().anyMatch(b -> "IN_BUSINESS_HOURS".equals(b.get("code"))),
                "处于营业时段内必须产生 IN_BUSINESS_HOURS 阻断项");
        assertNull(result.get("precheck_token"));
    }

    @Test
    void settle_whenInBusinessHours_throwsApiException() {
        shop.setOpen_time("10:00");
        shop.setClose_time("22:00");
        shop.setSettle_time("04:00");

        // 模拟当前时间为 18:30（晚餐营业高峰）
        java.time.Instant simulatedNow = LocalDateTime.of(2026, 10, 29, 18, 30, 0)
                .atZone(java.time.ZoneId.of("Asia/Shanghai")).toInstant();
        service.setClock(java.time.Clock.fixed(simulatedNow, java.time.ZoneId.of("Asia/Shanghai")));

        ApiException ex = assertThrows(ApiException.class, () ->
                service.settle(1, 1, "2026-10-29", "dummy_token", null, false, null));

        assertEquals(400, ex.getHttpStatus());
        assertEquals("DAILY_CLOSE_BLOCKED", ex.getErrorCode());
        assertTrue(ex.getMessage().contains("当前处于门店营业时段（10:00 ~ 22:00），禁止进行日结关账"));
    }

    @Test
    void precheck_whenOutsideBusinessHours_doesNotBlockDueToBusinessHours() {
        shop.setOpen_time("10:00");
        shop.setClose_time("22:00");
        shop.setSettle_time("04:00");

        // 模拟当前时间为 23:00（打烊后非营业时段）
        java.time.Instant simulatedNow = LocalDateTime.of(2026, 10, 29, 23, 0, 0)
                .atZone(java.time.ZoneId.of("Asia/Shanghai")).toInstant();
        service.setClock(java.time.Clock.fixed(simulatedNow, java.time.ZoneId.of("Asia/Shanghai")));

        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.count(any())).thenReturn(0);
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.precheck(1, "2026-10-29");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) result.get("blockers");
        assertTrue(blockers.stream().noneMatch(b -> "IN_BUSINESS_HOURS".equals(b.get("code"))),
                "打烊非营业时段内不得产生 IN_BUSINESS_HOURS 阻断");
    }
}

