package com.lanf.kds.delivery;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class CashierKdsProjectionQuantityTest {
    @Test void partialRefundAddsRemainingAndRefundedQuantity() {
        assertEquals(5, CashierKdsProjectionService.originalQuantity(3, 2, false));
    }

    @Test void fullRefundDoesNotDoubleCountStoredQuantity() {
        assertEquals(3, CashierKdsProjectionService.originalQuantity(3, 3, true));
        assertEquals(3, CashierKdsProjectionService.originalQuantity(2, 3, true));
    }
}
