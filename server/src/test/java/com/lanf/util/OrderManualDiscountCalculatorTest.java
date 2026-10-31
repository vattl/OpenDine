package com.lanf.util;

import com.lanf.entity.Order;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class OrderManualDiscountCalculatorTest {

    @Test
    void payRateNineFold() {
        Order o = new Order();
        o.setSett_amount(100d);
        o.setService_fee(0d);
        assertEquals(10d, OrderManualDiscountCalculator.resolveDiscountYuan(o, null, 0.9, false));
    }

    @Test
    void fixedDiscountAmount() {
        Order o = new Order();
        o.setSett_amount(80d);
        o.setService_fee(5d);
        assertEquals(15d, OrderManualDiscountCalculator.resolveDiscountYuan(o, 15d, null, false));
    }

    @Test
    void wipeZero() {
        Order o = new Order();
        o.setSett_amount(100.3d);
        o.setService_fee(0d);
        o.setDiscount_amount(0d);
        assertEquals(0.3d, OrderManualDiscountCalculator.resolveDiscountYuan(o, null, null, true));
    }

    @Test
    void requiresOneMode() {
        Order o = new Order();
        o.setSett_amount(10d);
        assertThrows(IllegalArgumentException.class,
                () -> OrderManualDiscountCalculator.resolveDiscountYuan(o, null, null, false));
    }
}
