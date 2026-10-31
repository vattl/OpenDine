package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.service.IOrderService;
import com.lanf.service.InviteService;
import com.lanf.service.PaymentLedgerService;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class WechatRefundSettlementServiceTest {

    private final IOrderService orderService = mock(IOrderService.class);
    private final PaymentRefundLedger ledger = mock(PaymentRefundLedger.class);
    private final InviteService inviteService = mock(InviteService.class);
    private final PaymentLedgerService paymentLedgerService = mock(PaymentLedgerService.class);
    private final WechatRefundSettlementService service =
            new WechatRefundSettlementService(orderService, ledger, inviteService);

    WechatRefundSettlementServiceTest() {
        ReflectionTestUtils.setField(service, "paymentLedgerService", paymentLedgerService);
    }

    private static Order order(String orderNo, double paidYuan, double refundedYuan) {
        Order o = new Order();
        o.setId(1);
        o.setOrder_no(orderNo);
        o.setShop_id(7);
        o.setSett_amount(paidYuan);
        o.setService_fee(0d);
        o.setDiscount_amount(0d);
        o.setRefund_amount(refundedYuan);
        return o;
    }

    @Test
    void settleAppliesRefundAndMarksLedgerSuccess() {
        Order o = order("ORD-1", 100.0, 0.0);
        o.setPay_amount_wechat(100d);
        o.setTransaction_id("WX-TX-1");
        PaymentLedger original = PaymentLedger.builder().id(51L).shop_id(7).order_id(1L)
                .order_no("ORD-1").entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_WECHAT).amount_fen(10000)
                .status(PaymentLedger.STATUS_SUCCEEDED).provider_transaction_id("WX-TX-1").build();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);
        when(ledger.beginCallback(anyInt(), anyString(), anyString(), anyInt())).thenReturn(true);
        when(orderService.updateById(o)).thenReturn(true);
        when(paymentLedgerService.listByOrder(7, "ORD-1")).thenReturn(Collections.singletonList(original));

        boolean applied = service.settle("ORD-1", "RF-1", 3000, "notify");

        assertTrue(applied);
        assertEquals(30.0, o.getRefund_amount(), 0.001);
        assertTrue(o.getRemark().contains("【退款到账·部分】30.0元"));
        verify(ledger).markSuccess("RF-1", 3000);
        verify(inviteService).reconcileFirstOrderInviteRewardOnRefund(o);
        InOrder sequence = inOrder(paymentLedgerService, orderService, ledger);
        sequence.verify(paymentLedgerService).recordRefund(
                o, PaymentLedger.CHANNEL_WECHAT, 3000, null,
                "REF_RF-1", null, 51L, "RF-1");
        sequence.verify(orderService).updateById(o);
        sequence.verify(ledger).markSuccess("RF-1", 3000);
    }

    @Test
    void settleWhenAuthoritativeRefundLedgerFails_doesNotPersistOrderProjection() {
        Order o = order("ORD-FAIL", 100.0, 0.0);
        o.setPay_amount_wechat(100d);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);
        when(ledger.beginCallback(anyInt(), anyString(), anyString(), anyInt())).thenReturn(true);
        when(paymentLedgerService.recordRefund(any(), anyString(), anyInt(), any(), anyString(), any(), any(), anyString()))
                .thenThrow(new IllegalStateException("ledger down"));

        assertThrows(IllegalStateException.class,
                () -> service.settle("ORD-FAIL", "RF-FAIL", 3000, "notify"));

        verify(orderService, never()).updateById(any());
        verify(ledger, never()).markSuccess(anyString(), anyInt());
    }

    @Test
    void settleSkipsWhenLedgerAlreadyApplied() {
        Order o = order("ORD-1", 100.0, 0.0);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);
        when(ledger.beginCallback(anyInt(), anyString(), anyString(), anyInt())).thenReturn(false);

        boolean applied = service.settle("ORD-1", "RF-1", 3000, "compensate");

        assertFalse(applied);
        verify(orderService, never()).updateById(any());
        verify(ledger, never()).markSuccess(anyString(), anyInt());
    }

    @Test
    void settleTruncatesToRemainingRefundable() {
        Order o = order("ORD-1", 10.0, 0.0);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);
        when(ledger.beginCallback(anyInt(), anyString(), anyString(), anyInt())).thenReturn(true);
        when(orderService.updateById(o)).thenReturn(true);

        boolean applied = service.settle("ORD-1", "RF-1", 3000, "notify");

        assertTrue(applied);
        assertEquals(10.0, o.getRefund_amount(), 0.001);
        verify(ledger).markSuccess("RF-1", 1000);
    }

    @Test
    void settleWithNoRemainingMarksSuccessZeroToStopRetry() {
        Order o = order("ORD-1", 10.0, 10.0);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);
        when(ledger.beginCallback(anyInt(), anyString(), anyString(), anyInt())).thenReturn(true);

        boolean applied = service.settle("ORD-1", "RF-1", 3000, "compensate");

        assertFalse(applied);
        verify(ledger).markSuccess("RF-1", 0);
        verify(orderService, never()).updateById(any());
    }

    @Test
    void settleOrderNotFoundReturnsFalse() {
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(null);

        boolean applied = service.settle("ORD-MISSING", "RF-1", 3000, "notify");

        assertFalse(applied);
        verifyNoInteractions(ledger);
    }

    @Test
    void settleInvalidParamsReturnsFalse() {
        assertFalse(service.settle("", "RF-1", 3000, "notify"));
        assertFalse(service.settle("ORD-1", "  ", 3000, "notify"));
        assertFalse(service.settle("ORD-1", "RF-1", 0, "notify"));
    }

    @Test
    void notificationSettlesOnlyTheRegisteredShopAndMerchantBinding() {
        Order o = order("ORD-1", 100.0, 0.0);
        o.setPay_amount_wechat(100d);
        o.setTransaction_id("WX-TX-1");
        o.setMerchant_config_id(9L);
        o.setMerchant_config_version(2);
        PaymentRefundLedger.Entry entry = refundEntry();
        when(ledger.beginVerifiedCallback("RF-1", 3000, "WX-TX-1", "MCH-7")).thenReturn(entry);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);
        when(ledger.beginCallback(7, "ORD-1", "RF-1", 3000)).thenReturn(true);
        when(orderService.updateById(o)).thenReturn(true);

        assertTrue(service.settleNotification("RF-1", 3000, "WX-TX-1", "MCH-7"));
        verify(ledger).markSuccess("RF-1", 3000);
    }

    @Test
    void notificationRejectsOrderWhoseMerchantBindingChanged() {
        Order o = order("ORD-1", 100.0, 0.0);
        o.setTransaction_id("WX-TX-1");
        o.setMerchant_config_id(10L);
        o.setMerchant_config_version(2);
        when(ledger.beginVerifiedCallback("RF-1", 3000, "WX-TX-1", "MCH-7"))
                .thenReturn(refundEntry());
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(o);

        assertThrows(IllegalStateException.class,
                () -> service.settleNotification("RF-1", 3000, "WX-TX-1", "MCH-7"));
        verify(ledger, never()).markSuccess(anyString(), anyInt());
    }

    @Test
    void notificationFailsWhenRegisteredOrderCannotBeLoaded() {
        when(ledger.beginVerifiedCallback("RF-1", 3000, "WX-TX-1", "MCH-7"))
                .thenReturn(refundEntry());
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(null);

        assertThrows(IllegalStateException.class,
                () -> service.settleNotification("RF-1", 3000, "WX-TX-1", "MCH-7"));
        verify(ledger, never()).markSuccess(anyString(), anyInt());
    }

    private static PaymentRefundLedger.Entry refundEntry() {
        return new PaymentRefundLedger.Entry(
                "ORD-1", "idem-1", "RF-1", 3000, 0, "REQUESTED",
                7, 9L, 2, "WX-TX-1", "MCH-7");
    }
}
