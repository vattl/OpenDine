package com.lanf.payment.service;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

class PaymentRefundLedgerTest {

    @Test
    void reserveRejectsAnotherPendingRefundForTheSameOrder() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(entry(
                                "ORD-1", "this-key", "RF-1", 1000)),
                        Collections.singletonList(guard("other-key")));
        PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

        PaymentRefundLedger.Entry result = ledger.reserve(
                7, "ORD-1", "this-key", "RF-1", 1000);

        assertEquals("REJECTED", result.status);
    }

    @Test
    void reserveReplaysTheSamePendingRefundKey() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(entry(
                                "ORD-1", "same-key", "RF-1", 1000)),
                        Collections.singletonList(guard("same-key")));
        PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

        assertDoesNotThrow(() -> ledger.reserve(
                7, "ORD-1", "same-key", "RF-1", 1000));
    }

    @Test
    void callbackDoesNotCreateAnUnknownRefundRequest() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyString())).thenReturn(Collections.emptyList());
        PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

        assertThrows(IllegalStateException.class,
                () -> ledger.beginCallback(7, "ORD-1", "RF-UNKNOWN", 1000));

        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void callbackRejectsAmountDifferentFromReservedRequest() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        Map<String, Object> reserved = entry("ORD-1", "same-key", "RF-1", 1000);
        reserved.put("shop_id", 7);
        when(jdbc.queryForList(anyString(), anyString()))
                .thenReturn(Collections.singletonList(reserved));
        PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

        assertThrows(IllegalStateException.class,
                () -> ledger.beginCallback(7, "ORD-1", "RF-1", 900));
    }

    @Test
    void idempotentReserveRejectsDifferentRefundNumber() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.singletonList(entry("ORD-1", "same-key", "RF-OLD", 1000)));
        PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

        assertThrows(IllegalStateException.class,
                () -> ledger.reserve(7, "ORD-1", "same-key", "RF-NEW", 1000));
    }

    @Test
    void verifiedCallbackRejectsWrongTransactionOrMerchant() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        Map<String, Object> reserved = boundEntry();
        when(jdbc.queryForList(anyString(), anyString()))
                .thenReturn(Collections.singletonList(reserved));
        PaymentRefundLedger ledger = new PaymentRefundLedger(jdbc);

        assertThrows(IllegalStateException.class,
                () -> ledger.beginVerifiedCallback("RF-1", 1000, "WRONG", "MCH-7"));
        assertThrows(IllegalStateException.class,
                () -> ledger.beginVerifiedCallback("RF-1", 1000, "WX-TX-1", "WRONG"));
    }

    private static Map<String, Object> guard(String key) {
        Map<String, Object> row = new HashMap<>();
        row.put("idempotency_key", key);
        return row;
    }

    private static Map<String, Object> entry(
            String orderNo,
            String key,
            String outRefundNo,
            int requestedFen) {
        Map<String, Object> row = new HashMap<>();
        row.put("order_no", orderNo);
        row.put("idempotency_key", key);
        row.put("out_refund_no", outRefundNo);
        row.put("requested_fen", requestedFen);
        row.put("applied_fen", 0);
        row.put("status", "REQUESTED");
        return row;
    }

    private static Map<String, Object> boundEntry() {
        Map<String, Object> row = entry("ORD-1", "same-key", "RF-1", 1000);
        row.put("shop_id", 7);
        row.put("merchant_config_id", 9L);
        row.put("merchant_config_version", 2);
        row.put("expected_transaction_id", "WX-TX-1");
        row.put("expected_mch_id", "MCH-7");
        return row;
    }
}
