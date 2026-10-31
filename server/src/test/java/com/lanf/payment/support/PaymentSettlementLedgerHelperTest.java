package com.lanf.payment.support;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shift;
import com.lanf.entity.Shop;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.IShiftService;
import com.lanf.service.IShopService;
import com.lanf.service.PaymentLedgerService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentSettlementLedgerHelperTest {

    private PaymentSettlementLedgerHelper helper;
    private PaymentLedgerService paymentLedgerService;
    private DrawerSessionService drawerSessionService;
    private IShiftService shiftService;
    private IShopService shopService;

    @BeforeEach
    void setUp() {
        helper = new PaymentSettlementLedgerHelper();
        paymentLedgerService = mock(PaymentLedgerService.class);
        drawerSessionService = mock(DrawerSessionService.class);
        shiftService = mock(IShiftService.class);
        shopService = mock(IShopService.class);

        ReflectionTestUtils.setField(helper, "paymentLedgerService", paymentLedgerService);
        ReflectionTestUtils.setField(helper, "drawerSessionService", drawerSessionService);
        ReflectionTestUtils.setField(helper, "shiftService", shiftService);
        ReflectionTestUtils.setField(helper, "shopService", shopService);
    }

    private Order buildOrder(Integer id, String orderNo, Integer shopId, String method, double amountYuan) {
        Order order = new Order();
        order.setId(id);
        order.setOrder_no(orderNo);
        order.setShop_id(shopId);
        order.setTransac_status("success");
        order.setPayment_method(method);
        order.setSett_amount(amountYuan);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        order.setPay_time(new Date());
        return order;
    }

    @Test
    void ensureOrderPaymentLedger_wechatPayOnline_recordsLedgerWithActiveSession() {
        Order order = buildOrder(1, "ORD-WX-001", 10, "微信支付", 88.00);
        order.setPay_amount_wechat(88.00);

        DrawerSession session = new DrawerSession();
        session.setId(501L);
        session.setTerminal_id("TERM-01");
        session.setOpened_by(1001);
        when(drawerSessionService.getActiveSession(10, null, null)).thenReturn(session);

        Shift shift = new Shift();
        shift.setId(201L);
        shift.setAdmin_id(1001);
        when(shiftService.getOne(any(Wrapper.class))).thenReturn(shift);

        PaymentLedger ledger = PaymentLedger.builder()
                .id(1L)
                .channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(8800)
                .drawer_session_id(501L)
                .build();
        when(paymentLedgerService.recordSettlement(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(Collections.singletonList(ledger));

        List<PaymentLedger> result = helper.ensureOrderPaymentLedger(order, null, null);

        assertEquals(1, result.size());
        assertEquals(PaymentLedger.CHANNEL_WECHAT, result.get(0).getChannel());
        assertEquals(501L, result.get(0).getDrawer_session_id());

        ArgumentCaptor<Map<String, Integer>> channelsCaptor = ArgumentCaptor.forClass(Map.class);
        verify(paymentLedgerService).recordSettlement(
                eq(order),
                eq(1001),
                any(),
                eq("TERM-01"),
                eq(501L),
                eq(201L),
                any(),
                channelsCaptor.capture(),
                any()
        );
        assertEquals(8800, channelsCaptor.getValue().get(PaymentLedger.CHANNEL_WECHAT));
    }

    @Test
    void ensureOrderPaymentLedger_idempotentWhenAlreadyRecorded() {
        Order order = buildOrder(2, "ORD-WX-002", 10, "微信支付", 50.00);
        PaymentLedger existing = PaymentLedger.builder()
                .id(10L)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(5000)
                .build();

        when(paymentLedgerService.listByOrder(10, "ORD-WX-002"))
                .thenReturn(Collections.singletonList(existing));

        List<PaymentLedger> result = helper.ensureOrderPaymentLedger(order, null, null);

        assertEquals(1, result.size());
        assertEquals(10L, result.get(0).getId());
        verify(paymentLedgerService, never()).recordSettlement(any(), any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void ensureOrderPaymentLedger_withFallbackShiftAndSession() {
        Order order = buildOrder(3, "ORD-WX-003", 10, "微信支付", 30.00);

        PaymentLedger ledger = PaymentLedger.builder()
                .id(3L)
                .channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(3000)
                .drawer_session_id(888L)
                .build();
        when(paymentLedgerService.recordSettlement(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(Collections.singletonList(ledger));

        List<PaymentLedger> result = helper.ensureOrderPaymentLedger(order, 888L, 999);

        assertEquals(1, result.size());
        verify(paymentLedgerService).recordSettlement(
                eq(order),
                eq(999),
                any(),
                any(),
                eq(888L),
                any(),
                any(),
                any(),
                any()
        );
    }

    @Test
    void ensureOrderPaymentLedger_receivableOrderDoesNotFabricatePayment() {
        Order order = buildOrder(4, "ORD-AR-001", 10, "挂账", 128.00);

        List<PaymentLedger> result = helper.ensureOrderPaymentLedger(order, null, null);

        assertTrue(result.isEmpty());
        verify(paymentLedgerService, never()).listByOrder(any(), any());
        verify(paymentLedgerService, never()).recordSettlement(any(), any(), any(), any(), any(), any(), any(), any(), any());
    }
}
