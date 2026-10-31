package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.CashMovement;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shift;
import com.lanf.mapper.CashMovementMapper;
import com.lanf.mapper.DrawerSessionMapper;
import com.lanf.service.impl.DrawerSessionServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DrawerSessionServiceTest {

    private DrawerSessionServiceImpl service;
    private DrawerSessionMapper drawerMapper;
    private CashMovementMapper cashMovementMapper;
    private IShiftService shiftService;
    private PaymentLedgerService paymentLedgerService;
    private IOrderService orderService;
    private IMemberRechargeService memberRechargeService;

    @BeforeEach
    void setUp() {
        service = new DrawerSessionServiceImpl();
        drawerMapper = mock(DrawerSessionMapper.class);
        cashMovementMapper = mock(CashMovementMapper.class);
        shiftService = mock(IShiftService.class);
        paymentLedgerService = mock(PaymentLedgerService.class);
        orderService = mock(IOrderService.class);
        memberRechargeService = mock(IMemberRechargeService.class);

        ReflectionTestUtils.setField(service, "baseMapper", drawerMapper);
        ReflectionTestUtils.setField(service, "cashMovementMapper", cashMovementMapper);
        ReflectionTestUtils.setField(service, "shiftService", shiftService);
        ReflectionTestUtils.setField(service, "paymentLedgerService", paymentLedgerService);
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "memberRechargeService", memberRechargeService);
    }

    @Test
    void openSession_success_createsSessionAndOpeningFloatMovement() {
        when(drawerMapper.selectOne(any())).thenReturn(null); // No existing or active
        when(drawerMapper.insert(any(DrawerSession.class))).thenReturn(1);
        when(cashMovementMapper.insert(any(CashMovement.class))).thenReturn(1);

        DrawerSession session = service.openSession(
                10, "POS-01", "DEFAULT", 99, 10000, "2026-10-03", "REQ-OPEN-01"
        );

        assertNotNull(session);
        assertEquals(10, session.getShop_id());
        assertEquals("POS-01", session.getTerminal_id());
        assertEquals(DrawerSession.STATE_OPEN, session.getState());
        assertEquals(10000, session.getOpening_float_fen());

        verify(drawerMapper, times(1)).insert(any(DrawerSession.class));

        ArgumentCaptor<CashMovement> cmCaptor = ArgumentCaptor.forClass(CashMovement.class);
        verify(cashMovementMapper, times(1)).insert(cmCaptor.capture());
        CashMovement cm = cmCaptor.getValue();
        assertEquals(CashMovement.TYPE_OPENING_FLOAT, cm.getMovement_type());
        assertEquals(10000, cm.getAmount_fen());
        assertEquals(10000, cm.getCurrent_balance_fen());
    }

    @Test
    void openSession_alreadyActive_throwsIllegalStateException() {
        DrawerSession active = DrawerSession.builder()
                .id(1L)
                .session_no("DS_ACTIVE")
                .state(DrawerSession.STATE_OPEN)
                .build();
        // First selectOne is for request_id (returns null), second is for getActiveSession (returns active)
        when(drawerMapper.selectOne(any())).thenReturn(null, active);

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                service.openSession(10, "POS-01", "DEFAULT", 99, 10000, "2026-10-03", "REQ-OPEN-02")
        );
        assertTrue(ex.getMessage().contains("未关闭的钱箱会话"));
        verify(cashMovementMapper, never()).insert(any(CashMovement.class));
    }

    @Test
    void openSession_idempotency_returnsExistingSession() {
        DrawerSession existing = DrawerSession.builder()
                .id(501L)
                .session_no("DS_EXISTING")
                .request_id("REQ-OPEN-IDEMP")
                .state(DrawerSession.STATE_OPEN)
                .build();
        when(drawerMapper.selectOne(any())).thenReturn(existing);

        DrawerSession result = service.openSession(
                10, "POS-01", "DEFAULT", 99, 10000, "2026-10-03", "REQ-OPEN-IDEMP"
        );

        assertEquals(501L, result.getId());
        verify(drawerMapper, never()).insert(any(DrawerSession.class));
        verify(cashMovementMapper, never()).insert(any(CashMovement.class));
    }

    @Test
    void calculateExpectedCashFen_tableDrivenReconciliation() {
        CashMovement m1 = CashMovement.builder().movement_type(CashMovement.TYPE_OPENING_FLOAT).amount_fen(10000).build();
        CashMovement m2 = CashMovement.builder().movement_type(CashMovement.TYPE_CASH_SALE).amount_fen(5000).build();
        CashMovement m3 = CashMovement.builder().movement_type(CashMovement.TYPE_CASH_REFUND).amount_fen(-2000).build();
        CashMovement m4 = CashMovement.builder().movement_type(CashMovement.TYPE_CASH_IN).amount_fen(3000).build();
        CashMovement m5 = CashMovement.builder().movement_type(CashMovement.TYPE_CASH_OUT).amount_fen(-1500).build();
        CashMovement m6 = CashMovement.builder().movement_type(CashMovement.TYPE_CASH_DROP).amount_fen(-4000).build();
        CashMovement m7 = CashMovement.builder().movement_type(CashMovement.TYPE_ADJUSTMENT).amount_fen(500).build();
        // COUNT and NO_SALE should be excluded from summation
        CashMovement mCount = CashMovement.builder().movement_type(CashMovement.TYPE_COUNT).amount_fen(0).build();
        CashMovement mNoSale = CashMovement.builder().movement_type(CashMovement.TYPE_NO_SALE).amount_fen(0).build();

        when(cashMovementMapper.selectList(any())).thenReturn(Arrays.asList(m1, m2, m3, m4, m5, m6, m7));

        int expectedFen = service.calculateExpectedCashFen(101L);
        // 10000 + 5000 - 2000 + 3000 - 1500 - 4000 + 500 = 11000 fen
        assertEquals(11000, expectedFen);
    }

    @Test
    void recordManualMovement_cashOutExceedsBalance_requiresApproval() {
        DrawerSession session = DrawerSession.builder()
                .id(102L)
                .shop_id(10)
                .state(DrawerSession.STATE_OPEN)
                .build();
        when(drawerMapper.selectById(102L)).thenReturn(session);

        // Current balance is 50.00 (5000 fen)
        CashMovement last = CashMovement.builder().current_balance_fen(5000).build();
        // First selectOne is for request_id check (null), second is for last movement check (last)
        when(cashMovementMapper.selectOne(any())).thenReturn(null, last);

        // Attempting to withdraw 60.00 (6000 fen) without approver -> rejected
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                service.recordManualMovement(
                        10, 102L, CashMovement.TYPE_CASH_OUT, 6000, "PETTY_CASH", "零用支出", 99, null, "REQ-OUT-01"
                )
        );
        assertTrue(ex.getMessage().contains("超额支取须主管授权"));

        // With manager approval (approverId = 88) -> allowed
        when(cashMovementMapper.selectOne(any())).thenReturn(null, last);
        when(cashMovementMapper.insert(any(CashMovement.class))).thenReturn(1);
        CashMovement movement = service.recordManualMovement(
                10, 102L, CashMovement.TYPE_CASH_OUT, 6000, "PETTY_CASH", "经店长特批零用支出", 99, 88, "REQ-OUT-02"
        );
        assertNotNull(movement);
        assertEquals(-6000, movement.getAmount_fen());
        assertEquals(-1000, movement.getCurrent_balance_fen());
    }

    @Test
    void closeSession_blindCountMatches_closesWithoutVarianceApproval() {
        DrawerSession session = DrawerSession.builder()
                .id(103L)
                .shop_id(10)
                .state(DrawerSession.STATE_OPEN)
                .opening_float_fen(10000)
                .build();
        when(drawerMapper.selectById(103L)).thenReturn(session);
        when(drawerMapper.updateById(any(DrawerSession.class))).thenReturn(1);

        CashMovement m1 = CashMovement.builder().movement_type(CashMovement.TYPE_OPENING_FLOAT).amount_fen(10000).build();
        when(cashMovementMapper.selectList(any())).thenReturn(Collections.singletonList(m1));

        DrawerSession closed = service.closeSession(
                10, 103L, 99, 10000, null, "账实相符", null, "REQ-CLOSE-01"
        );

        assertEquals(DrawerSession.STATE_CLOSED, closed.getState());
        assertEquals(10000, closed.getExpected_cash_fen());
        assertEquals(10000, closed.getCounted_cash_fen());
        assertEquals(0, closed.getVariance_fen());

        verify(drawerMapper, times(1)).updateById(any(DrawerSession.class));
        verify(cashMovementMapper, times(1)).insert(any(CashMovement.class)); // Only COUNT, no ADJUSTMENT
    }

    @Test
    void closeSession_varianceExceeds50Yuan_requiresManagerApproval() {
        DrawerSession session = DrawerSession.builder()
                .id(104L)
                .shop_id(10)
                .state(DrawerSession.STATE_OPEN)
                .opening_float_fen(10000) // Expected = 10000 fen (100 yuan)
                .build();
        when(drawerMapper.selectById(104L)).thenReturn(session);

        CashMovement m1 = CashMovement.builder().movement_type(CashMovement.TYPE_OPENING_FLOAT).amount_fen(10000).build();
        when(cashMovementMapper.selectList(any())).thenReturn(Collections.singletonList(m1));

        // Cashier counted 2000 fen (20 yuan) -> shortage of 8000 fen (80 yuan, > 50 yuan limit)
        // 1. Without approvedBy: throws exception
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                service.closeSession(
                        10, 104L, 99, 2000, "SHORTAGE", "短款80元", null, "REQ-CLOSE-02"
                )
        );
        assertTrue(ex.getMessage().contains("超过 50 元须店长二次授权核验"));

        // 2. With manager approvedBy = 88: succeeds and generates COUNT and ADJUSTMENT
        when(drawerMapper.updateById(any(DrawerSession.class))).thenReturn(1);
        when(cashMovementMapper.insert(any(CashMovement.class))).thenReturn(1);

        DrawerSession approvedClosed = service.closeSession(
                10, 104L, 99, 2000, "SHORTAGE", "短款80元店长确认", 88, "REQ-CLOSE-03"
        );

        assertEquals(DrawerSession.STATE_CLOSED, approvedClosed.getState());
        assertEquals(-8000, approvedClosed.getVariance_fen());
        assertEquals(88, approvedClosed.getApproved_by());
        // Verify 2 movements inserted: COUNT (实盘) + ADJUSTMENT (平账)
        verify(cashMovementMapper, times(2)).insert(any(CashMovement.class));
    }

    @Test
    void closeSession_closedWithDifferentRequest_returnsStableConflict() {
        DrawerSession session = DrawerSession.builder()
                .id(104L)
                .shop_id(10)
                .state(DrawerSession.STATE_CLOSED)
                .close_request_id("close-request-a")
                .build();
        when(drawerMapper.selectById(104L)).thenReturn(session);

        ApiException ex = assertThrows(ApiException.class, () ->
                service.closeSession(10, 104L, 99, 2000, null, null, null, "close-request-b")
        );

        assertEquals(409, ex.getHttpStatus());
        assertEquals("SHIFT_ALREADY_CLOSED", ex.getErrorCode());
    }

    @Test
    void getShiftSummaryReport_openSession_isRejectedBeforeBlindCount() {
        when(drawerMapper.selectById(106L)).thenReturn(DrawerSession.builder()
                .id(106L).shop_id(10).state(DrawerSession.STATE_OPEN).build());

        ApiException ex = assertThrows(ApiException.class, () -> service.getShiftSummaryReport(106L));

        assertEquals(409, ex.getHttpStatus());
        assertEquals("SHIFT_NOT_CLOSED", ex.getErrorCode());
    }

    @Test
    void getShiftSummaryReport_returnsCashAndMultiChannelBreakdown() {
        DrawerSession session = DrawerSession.builder()
                .id(105L)
                .session_no("DS_105")
                .shop_id(10)
                .state(DrawerSession.STATE_CLOSED)
                .opening_float_fen(5000)
                .expected_cash_fen(12000)
                .counted_cash_fen(12000)
                .variance_fen(0)
                .build();
        when(drawerMapper.selectById(105L)).thenReturn(session);

        CashMovement mSale = CashMovement.builder().movement_type(CashMovement.TYPE_CASH_SALE).amount_fen(7000).build();
        when(cashMovementMapper.selectList(any())).thenReturn(Collections.singletonList(mSale));

        PaymentLedger plCash = PaymentLedger.builder().channel(PaymentLedger.CHANNEL_CASH).amount_fen(7000).order_no("ORD-1").build();
        PaymentLedger plWx = PaymentLedger.builder().channel(PaymentLedger.CHANNEL_WECHAT).amount_fen(8000).order_no("ORD-2").build();
        when(paymentLedgerService.list(any())).thenReturn(Arrays.asList(plCash, plWx));
        when(memberRechargeService.summarizeSuccessfulByDrawerSession(105L))
                .thenReturn(new MemberRechargeSummary(2, 15000, 1000));

        Map<String, Object> report = service.getShiftSummaryReport(105L);

        assertNotNull(report);
        assertEquals(105L, report.get("session_id"));

        @SuppressWarnings("unchecked")
        Map<String, Object> cashSummary = (Map<String, Object>) report.get("cash_summary");
        assertEquals(50.0, cashSummary.get("opening_float_yuan"));
        assertEquals(70.0, cashSummary.get("cash_sale_yuan"));
        assertEquals(120.0, cashSummary.get("expected_cash_yuan"));
        assertEquals(0.0, cashSummary.get("variance_yuan"));

        @SuppressWarnings("unchecked")
        Map<String, Object> channelSummary = (Map<String, Object>) report.get("channel_summary");
        assertEquals(150.0, channelSummary.get("total_net_yuan"));
        assertEquals(2, channelSummary.get("distinct_orders_count"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> channels = (List<Map<String, Object>>) report.get("channels");
        assertEquals(2, channels.size());
        assertTrue(channels.get(0).containsKey("net_amount_fen"));
        assertTrue(report.containsKey("audit_events"));
        assertTrue(report.containsKey("integrity"));

        @SuppressWarnings("unchecked")
        Map<String, Object> recharge = (Map<String, Object>) report.get("member_recharge_summary");
        assertEquals(2L, recharge.get("success_count"));
        assertEquals(15000L, recharge.get("principal_fen"));
        assertEquals(1000L, recharge.get("gift_fen"));
        assertEquals(16000L, recharge.get("credited_total_fen"));
    }

    @Test
    void getShiftSummaryReport_splitsQrChannelsByOrderPaymentMethod() {
        DrawerSession session = DrawerSession.builder()
                .id(107L).shop_id(10).state(DrawerSession.STATE_CLOSED).build();
        when(drawerMapper.selectById(107L)).thenReturn(session);
        when(cashMovementMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentLedgerService.list(any())).thenReturn(Arrays.asList(
                PaymentLedger.builder().channel(PaymentLedger.CHANNEL_WECHAT)
                        .amount_fen(8000).order_no("ORD-WX-QR").build(),
                PaymentLedger.builder().channel(PaymentLedger.CHANNEL_ALIPAY)
                        .amount_fen(9000).order_no("ORD-ALI-QR").build()));
        Order wx = new Order();
        wx.setOrder_no("ORD-WX-QR");
        wx.setPayment_method("微信收款码");
        Order ali = new Order();
        ali.setOrder_no("ORD-ALI-QR");
        ali.setPayment_method("支付宝收款码自动");
        when(orderService.list(any(Wrapper.class))).thenReturn(Arrays.asList(wx, ali));

        Map<String, Object> report = service.getShiftSummaryReport(107L);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> channels = (List<Map<String, Object>>) report.get("channels");
        assertEquals("wechat_qr", channels.get(0).get("code"));
        assertEquals("微信收款码", channels.get(0).get("label"));
        assertEquals("alipay_qr", channels.get(1).get("code"));
        assertEquals("支付宝收款码", channels.get(1).get("label"));
    }

    @Test
    void getWorkbench_includesCurrentShiftRechargeSummary() {
        DrawerSession active = DrawerSession.builder()
                .id(108L).shop_id(10).state(DrawerSession.STATE_OPEN).business_day("2026-10-09").build();
        when(drawerMapper.selectList(any())).thenReturn(Collections.singletonList(active), Collections.emptyList());
        when(cashMovementMapper.selectOne(any())).thenReturn(null);
        when(memberRechargeService.summarizeSuccessfulByDrawerSession(108L))
                .thenReturn(new MemberRechargeSummary(1, 20000, 2000));

        Map<String, Object> workbench = service.getWorkbench(10, 99);

        @SuppressWarnings("unchecked")
        Map<String, Object> currentShift = (Map<String, Object>) workbench.get("current_shift");
        @SuppressWarnings("unchecked")
        Map<String, Object> recharge = (Map<String, Object>) currentShift.get("member_recharge_summary");
        assertEquals(1L, recharge.get("success_count"));
        assertEquals(20000L, recharge.get("principal_fen"));
        assertEquals(2000L, recharge.get("gift_fen"));
    }
}
