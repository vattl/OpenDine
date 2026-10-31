package com.lanf.payment.support;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PaymentOrderNoUtilTest {

    @Test
    void refundNumberIsStableForRetriesAndChangesForNextRefund() {
        String first = PaymentOrderNoUtil.buildOutRefundNo("ORD202607310001", 0, 2500);
        String retry = PaymentOrderNoUtil.buildOutRefundNo("ORD202607310001", 0, 2500);
        String next = PaymentOrderNoUtil.buildOutRefundNo("ORD202607310001", 2500, 2500);

        assertEquals(first, retry);
        assertNotEquals(first, next);
        assertTrue(first.length() <= 64);
    }

    @Test
    void refundNumberUsesPersistentIdempotencyKeyAcrossCallbackStateChanges() {
        String first = PaymentOrderNoUtil.buildOutRefundNo(
                "ORD202607310001", "refund-request-001");
        String retryAfterCallback = PaymentOrderNoUtil.buildOutRefundNo(
                "ORD202607310001", "refund-request-001");
        String distinctRequest = PaymentOrderNoUtil.buildOutRefundNo(
                "ORD202607310001", "refund-request-002");

        assertEquals(first, retryAfterCallback);
        assertNotEquals(first, distinctRequest);
        assertTrue(first.length() <= 64);
    }
}
