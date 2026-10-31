package com.lanf.kds.support;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class KdsAdvanceRequestContextTest {
    @Test
    void normalizesSnapshotValues() {
        KdsAdvanceRequestContext context = new KdsAdvanceRequestContext(12, " A08 ", " 羊肉串 ");
        assertTrue(context.hasAnyExpectation());
        assertEquals(12, context.getExpectedOrderId());
        assertEquals("A08", context.getExpectedTableNumber());
        assertEquals("羊肉串", context.getExpectedDishName());
    }

    @Test
    void blankSnapshotHasNoExpectation() {
        assertFalse(new KdsAdvanceRequestContext(null, " ", null).hasAnyExpectation());
    }
}
