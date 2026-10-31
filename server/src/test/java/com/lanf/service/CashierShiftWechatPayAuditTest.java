package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.controller.cashier.CashierShiftController;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shift;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class CashierShiftWechatPayAuditTest {

    private CashierShiftController shiftController;
    private PaymentLedgerService paymentLedgerService;
    private IShiftService shiftService;
    private DrawerSessionService drawerSessionService;

    @BeforeEach
    void setUp() {
        shiftController = new CashierShiftController();
        paymentLedgerService = mock(PaymentLedgerService.class);
        shiftService = mock(IShiftService.class);
        drawerSessionService = mock(DrawerSessionService.class);

        ReflectionTestUtils.setField(shiftController, "paymentLedgerService", paymentLedgerService);
        ReflectionTestUtils.setField(shiftController, "shiftService", shiftService);
        ReflectionTestUtils.setField(shiftController, "drawerSessionService", drawerSessionService);
    }

    @Test
    void shiftStats_includesBothWechatQrAndOnlineWechatPay() {
        Shift shift = new Shift();
        shift.setId(100L);
        shift.setDrawer_session_id(555L);
        shift.setShop_id(1);
        shift.setStart_time(new Date(System.currentTimeMillis() - 3600000));

        PaymentLedger qrLedger = PaymentLedger.builder()
                .id(1L)
                .order_no("ORD-QR-001")
                .channel(PaymentLedger.CHANNEL_WECHAT_QR)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .amount_fen(5000)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .drawer_session_id(555L)
                .build();

        PaymentLedger onlineWxLedger = PaymentLedger.builder()
                .id(2L)
                .order_no("ORD-WX-002")
                .channel(PaymentLedger.CHANNEL_WECHAT)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .amount_fen(8800)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .drawer_session_id(555L)
                .build();

        when(paymentLedgerService.list(any(Wrapper.class)))
                .thenReturn(Arrays.asList(qrLedger, onlineWxLedger));

        Object[] stats = (Object[]) ReflectionTestUtils.invokeMethod(shiftController, "shiftStats", shift);
        assertNotNull(stats);
        assertEquals(2, (Integer) stats[0], "Order count must include both QR code and online WeChat Pay");
        assertEquals(new BigDecimal("138.00"), (BigDecimal) stats[1], "Total revenue must sum both channels (50.00 + 88.00 = 138.00)");
    }
}
