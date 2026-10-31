package com.lanf.util;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OrderBusinessDayRangeResolverTest {

    @Test
    void beforeFour_shouldUsePreviousBusinessDay() {
        OrderBusinessDayRangeResolver.Range range = OrderBusinessDayRangeResolver.resolve(
                LocalDateTime.of(2026, 8, 2, 3, 59, 59));

        assertEquals(LocalDateTime.of(2026, 8, 1, 16, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 8, 2, 4, 0), range.getEnd());
    }

    @Test
    void closedHours_shouldKeepLastCompletedBusinessDay() {
        OrderBusinessDayRangeResolver.Range range = OrderBusinessDayRangeResolver.resolve(
                LocalDateTime.of(2026, 8, 2, 15, 59, 59));

        assertEquals(LocalDateTime.of(2026, 8, 1, 16, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 8, 2, 4, 0), range.getEnd());
    }

    @Test
    void atFour_shouldExcludeOrdersFromTheClosedPeriod() {
        OrderBusinessDayRangeResolver.Range range = OrderBusinessDayRangeResolver.resolve(
                LocalDateTime.of(2026, 8, 2, 4, 0));

        assertEquals(LocalDateTime.of(2026, 8, 1, 16, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 8, 2, 4, 0), range.getEnd());
    }

    @Test
    void fromSixteen_shouldStartNewBusinessDay() {
        OrderBusinessDayRangeResolver.Range range = OrderBusinessDayRangeResolver.resolve(
                LocalDateTime.of(2026, 8, 2, 16, 0));

        assertEquals(LocalDateTime.of(2026, 8, 2, 16, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 8, 3, 4, 0), range.getEnd());
    }
}
