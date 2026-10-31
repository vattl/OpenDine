package com.lanf.payment.service;

import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.PaymentLedgerService;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;

class OrderLedgerConsistencyServiceTest {

    private final PaymentLedgerService ledgerService = mock(PaymentLedgerService.class);
    private final OrderLedgerConsistencyService service = new OrderLedgerConsistencyService(ledgerService);

    @Test
    void audit_balancedPaymentAndRefund_matchesCurrentOrderChannelProjection() {
        Order order = paidOrder("ORD-1");
        order.setPay_amount_cash(75d);
        order.setPay_amount_wechat(25d);
        when(ledgerService.list(any())).thenReturn(Arrays.asList(
                ledger(1L, PaymentLedger.ENTRY_TYPE_PAYMENT, PaymentLedger.CHANNEL_CASH, 10000),
                ledger(2L, PaymentLedger.ENTRY_TYPE_REFUND, PaymentLedger.CHANNEL_CASH, -2500),
                ledger(3L, PaymentLedger.ENTRY_TYPE_PAYMENT, PaymentLedger.CHANNEL_WECHAT, 2500)));

        assertTrue(service.audit(Collections.singletonList(order)).isEmpty());
    }

    @Test
    void audit_missingRefundLedger_returnsMismatch() {
        Order order = paidOrder("ORD-2");
        order.setPay_amount_cash(75d);
        PaymentLedger payment = ledger(1L, PaymentLedger.ENTRY_TYPE_PAYMENT, PaymentLedger.CHANNEL_CASH, 10000);
        payment.setOrder_no("ORD-2");
        when(ledgerService.list(any())).thenReturn(Collections.singletonList(payment));

        java.util.List<OrderLedgerConsistencyService.Issue> issues =
                service.audit(Collections.singletonList(order));

        assertEquals(1, issues.size());
        assertEquals("ORD-2", issues.get(0).getOrderNo());
        assertEquals(Integer.valueOf(7500), issues.get(0).getExpectedByChannel().get(PaymentLedger.CHANNEL_CASH));
        assertEquals(Integer.valueOf(10000), issues.get(0).getActualByChannel().get(PaymentLedger.CHANNEL_CASH));
    }

    @Test
    void audit_missingAllLedgers_explainsMissingLedgerAndSignedDifference() {
        Order order = paidOrder("ORD-MISSING");
        order.setPayment_method("现金支付");
        order.setPay_amount_cash(100d);
        when(ledgerService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> detail = service.audit(Collections.singletonList(order)).get(0).toMap();

        assertEquals(1, detail.get("order_id"));
        assertEquals(7, detail.get("shop_id"));
        assertEquals("现金支付", detail.get("payment_method"));
        assertEquals(10000, detail.get("expected_total_fen"));
        assertEquals(0, detail.get("ledger_total_fen"));
        assertEquals(-10000, detail.get("difference_fen"));
        assertTrue(((List<?>) detail.get("reason_codes")).contains("LEDGER_MISSING"));
        assertTrue(((List<?>) detail.get("reason_codes")).contains("TOTAL_AMOUNT_SHORT"));
        assertTrue(String.valueOf(detail.get("reason")).contains("缺少成功资金流水"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> channelDifferences =
                (List<Map<String, Object>>) detail.get("channel_differences");
        assertEquals(1, channelDifferences.size());
        assertEquals(PaymentLedger.CHANNEL_CASH, channelDifferences.get(0).get("channel"));
        assertEquals("CHANNEL_LEDGER_MISSING", channelDifferences.get(0).get("reason_code"));
        assertEquals(-10000, channelDifferences.get(0).get("difference_fen"));
    }

    @Test
    void audit_wrongLedgerChannel_explainsMissingAndUnexpectedChannels() {
        Order order = paidOrder("ORD-WRONG-CHANNEL");
        order.setPayment_method("微信支付");
        order.setPay_amount_wechat(100d);
        PaymentLedger payment = ledger(1L, PaymentLedger.ENTRY_TYPE_PAYMENT,
                PaymentLedger.CHANNEL_CASH, 10000);
        payment.setOrder_no("ORD-WRONG-CHANNEL");
        when(ledgerService.list(any())).thenReturn(Collections.singletonList(payment));

        OrderLedgerConsistencyService.Issue issue =
                service.audit(Collections.singletonList(order)).get(0);
        Map<String, Object> detail = issue.toMap();

        assertEquals(0, detail.get("difference_fen"));
        assertTrue(issue.getReasonCodes().contains("CHANNEL_LEDGER_MISSING"));
        assertTrue(issue.getReasonCodes().contains("UNEXPECTED_LEDGER_CHANNEL"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> channelDifferences =
                (List<Map<String, Object>>) detail.get("channel_differences");
        assertEquals(2, channelDifferences.size());
    }

    @Test
    void audit_sameChannelExcess_explainsTotalAndChannelExcess() {
        Order order = paidOrder("ORD-EXCESS");
        order.setPay_amount_cash(75d);
        PaymentLedger payment = ledger(1L, PaymentLedger.ENTRY_TYPE_PAYMENT,
                PaymentLedger.CHANNEL_CASH, 10000);
        payment.setOrder_no("ORD-EXCESS");
        when(ledgerService.list(any())).thenReturn(Collections.singletonList(payment));

        OrderLedgerConsistencyService.Issue issue =
                service.audit(Collections.singletonList(order)).get(0);

        assertEquals(2500, issue.toMap().get("difference_fen"));
        assertTrue(issue.getReasonCodes().contains("TOTAL_AMOUNT_EXCESS"));
        assertTrue(issue.getReasonCodes().contains("CHANNEL_AMOUNT_EXCESS"));
    }

    @Test
    void audit_receivableOrder_doesNotRequirePaymentLedger() {
        Order order = paidOrder("ORD-AR");
        order.setPayment_method(ReceivableService.PAYMENT_METHOD_RECEIVABLE);

        assertTrue(service.audit(Collections.singletonList(order)).isEmpty());
    }

    private static Order paidOrder(String orderNo) {
        Order order = new Order();
        order.setId(1);
        order.setShop_id(7);
        order.setOrder_no(orderNo);
        order.setTransac_status("success");
        order.setSett_amount(100d);
        return order;
    }

    private static PaymentLedger ledger(Long id, String type, String channel, int amountFen) {
        return PaymentLedger.builder().id(id).shop_id(7).order_id(1L).order_no("ORD-1")
                .entry_type(type).channel(channel).amount_fen(amountFen)
                .status(PaymentLedger.STATUS_SUCCEEDED).build();
    }
}
