package com.lanf.util;

import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertTrue;

class OrderNumberGeneratorTest {

    @Test
    void shouldGenerateOneThousandUniqueCanonicalNumbers() {
        Set<String> values = new HashSet<>();
        for (int index = 0; index < 1000; index++) {
            String orderNo = OrderNumberGenerator.next();
            assertTrue(orderNo.matches("^ORD\\d{17}$"));
            assertTrue(values.add(orderNo), "重复订单号：" + orderNo);
        }
    }
}
