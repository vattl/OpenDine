package com.lanf.controller.cashier;

import com.lanf.entity.CashMovement;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.R;
import com.lanf.entity.Shift;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.IPaymentService;
import com.lanf.service.IShiftService;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.MemberRechargeSummary;
import com.lanf.service.PaymentLedgerService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierShiftControllerTest {

    private CashierShiftController controller;
    private IShiftService shiftService;
    private IPaymentService paymentService;
    private DrawerSessionService drawerSessionService;
    private PaymentLedgerService paymentLedgerService;
    private IMemberRechargeService memberRechargeService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new CashierShiftController();
        shiftService = mock(IShiftService.class);
        paymentService = mock(IPaymentService.class);
        drawerSessionService = mock(DrawerSessionService.class);
        paymentLedgerService = mock(PaymentLedgerService.class);
        memberRechargeService = mock(IMemberRechargeService.class);
        request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(controller, "shiftService", shiftService);
        ReflectionTestUtils.setField(controller, "paymentService", paymentService);
        ReflectionTestUtils.setField(controller, "drawerSessionService", drawerSessionService);
        ReflectionTestUtils.setField(controller, "paymentLedgerService", paymentLedgerService);
        ReflectionTestUtils.setField(controller, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(controller, "request", request);

        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 99);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
    }

    @Test
    void start_delegatesToDrawerSessionServiceAndReturnsSessionInfo() {
        DrawerSession session = DrawerSession.builder()
                .id(100L)
                .session_no("DS_7_POS-01_100")
                .shop_id(7)
                .terminal_id("POS-01")
                .state(DrawerSession.STATE_OPEN)
                .business_day("2026-10-03")
                .build();
        when(drawerSessionService.openSession(eq(7), eq("POS-01"), any(), eq(99), eq(10000), any(), any()))
                .thenReturn(session);

        Shift shift = new Shift();
        shift.setId(88L);
        when(shiftService.getOne(any())).thenReturn(shift);

        Map<String, Object> body = new HashMap<>();
        body.put("start_cash", "100.00");
        body.put("terminal_id", "POS-01");

        R res = controller.start(body);
        assertEquals(0, res.get("code"));
        assertEquals(100L, res.get("sessionId"));
        assertEquals("DS_7_POS-01_100", res.get("session_no"));
        assertEquals("OPEN", res.get("state"));
    }

    @Test
    void handover_blindCount_closesDrawerSessionAndReturnsReport() {
        Shift current = new Shift();
        current.setId(88L);
        current.setDrawer_session_id(100L);
        current.setStart_cash(new BigDecimal("100.00"));
        when(shiftService.getOne(any())).thenReturn(current);

        DrawerSession closed = DrawerSession.builder()
                .id(100L)
                .state(DrawerSession.STATE_CLOSED)
                .counted_cash_fen(12000)
                .expected_cash_fen(12000)
                .variance_fen(0)
                .build();
        when(drawerSessionService.closeSession(eq(7), eq(100L), eq(99), eq(12000), any(), any(), any(), any()))
                .thenReturn(closed);

        Map<String, Object> report = new LinkedHashMap<>();
        report.put("session_id", 100L);
        when(drawerSessionService.getShiftSummaryReport(100L)).thenReturn(report);

        Map<String, Object> body = new HashMap<>();
        body.put("counted_cash", "120.00");

        R res = controller.handover(body);
        assertEquals(0, res.get("code"));
        assertNotNull(res.get("report"));
    }

    @Test
    void current_neverExposesExpectedCashBeforeBlindCountSubmission() {
        Shift current = new Shift();
        current.setId(88L);
        current.setDrawer_session_id(100L);
        when(shiftService.getOne(any())).thenReturn(current);

        DrawerSession active = DrawerSession.builder()
                .id(100L)
                .session_no("DS_100")
                .state(DrawerSession.STATE_OPEN)
                .opening_float_fen(10000)
                .build();
        when(drawerSessionService.getById(100L)).thenReturn(active);
        when(memberRechargeService.summarizeSuccessfulByDrawerSession(100L))
                .thenReturn(new MemberRechargeSummary(1, 10000, 1000));

        R resBlind = controller.current(false);
        assertEquals(0, resBlind.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> dsBlind = (Map<String, Object>) resBlind.get("drawer_session");
        assertNotNull(dsBlind);
        assertNull(dsBlind.get("expected_cash_yuan"));
        assertNull(dsBlind.get("expected_cash_fen"));
        assertNull(dsBlind.get("variance_yuan"));
        assertNull(dsBlind.get("variance_fen"));
        @SuppressWarnings("unchecked")
        Map<String, Object> recharge = (Map<String, Object>) resBlind.get("member_recharge_summary");
        assertEquals(10000L, recharge.get("principal_fen"));
        assertEquals(1000L, recharge.get("gift_fen"));

        // Legacy query flag must not bypass blind-count protection.
        when(drawerSessionService.calculateExpectedCashFen(100L)).thenReturn(15000);
        R resWithLegacyFlag = controller.current(true);
        @SuppressWarnings("unchecked")
        Map<String, Object> dsWithLegacyFlag = (Map<String, Object>) resWithLegacyFlag.get("drawer_session");
        assertNull(dsWithLegacyFlag.get("expected_cash_yuan"));
        assertNull(dsWithLegacyFlag.get("expected_cash_fen"));
    }

    @Test
    void cashMovement_recordsManualActionSuccessfully() {
        DrawerSession active = DrawerSession.builder().id(100L).state(DrawerSession.STATE_OPEN).build();
        when(drawerSessionService.getActiveSession(eq(7), any(), any())).thenReturn(active);

        CashMovement movement = CashMovement.builder()
                .movement_no("CM_IN_01")
                .movement_type(CashMovement.TYPE_CASH_IN)
                .amount_fen(5000)
                .current_balance_fen(15000)
                .build();
        when(drawerSessionService.recordManualMovement(eq(7), eq(100L), eq("CASH_IN"), eq(5000), any(), any(), eq(99), any(), any()))
                .thenReturn(movement);

        Map<String, Object> body = new HashMap<>();
        body.put("movement_type", "CASH_IN");
        body.put("amount", "50.00");
        body.put("remark", "零钱加钞");

        R res = controller.cashMovement(body);
        assertEquals(0, res.get("code"));
        assertEquals("CM_IN_01", res.get("movement_no"));
        assertEquals(50.0, res.get("amount_yuan"));
        assertEquals(150.0, res.get("current_balance_yuan"));
    }

    @Test
    void report_returnsSummaryReport() {
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("session_id", 100L);
        summary.put("shop_id", 7);
        when(drawerSessionService.getShiftSummaryReport(100L)).thenReturn(summary);

        R res = controller.report(100L);
        assertEquals(0, res.get("code"));
        assertNotNull(res.get("report"));
    }
}
