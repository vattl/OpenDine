package com.lanf.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OrderPackagingFeeCalculatorTest {

    @Test
    void packagingFee_shouldCoverHundredYuanBoundaries() {
        assertEquals(0d, OrderPackagingFeeCalculator.calcYuan(0d));
        assertEquals(1d, OrderPackagingFeeCalculator.calcYuan(99.99d));
        assertEquals(1d, OrderPackagingFeeCalculator.calcYuan(100d));
        assertEquals(2d, OrderPackagingFeeCalculator.calcYuan(100.01d));
    }

    @Test
    void takeOutSettlement_shouldAddPackagingWhenFrontSendsGoodsSubtotal() {
        assertEquals(16d,
                OrderPackagingFeeCalculator.resolveSettForTakeOut(15d, 15d));
        assertEquals(100.99d,
                OrderPackagingFeeCalculator.resolveSettForTakeOut(99.99d, 99.99d));
        assertEquals(101d,
                OrderPackagingFeeCalculator.resolveSettForTakeOut(100d, 100d));
        assertEquals(102.01d,
                OrderPackagingFeeCalculator.resolveSettForTakeOut(100.01d, 100.01d));
        assertEquals(15d,
                OrderPackagingFeeCalculator.resolveSettForDineIn(15d, 15d));
    }
}
