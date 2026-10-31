package com.lanf.util;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OrderListTimeRangeResolverTest {

    @Test
    void earlyMorningDefaultsToOperationalWindow() {
        OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 7, 20, 1, 30), null, null);

        assertEquals(LocalDateTime.of(2026, 7, 19, 4, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 7, 20, 4, 0), range.getEnd());
    }

    @Test
    void daytimeDefaultsToOperationalWindow() {
        OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 7, 20, 15, 0), null, null);

        assertEquals(LocalDateTime.of(2026, 7, 20, 4, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 7, 21, 4, 0), range.getEnd());
    }

    @Test
    void customSettleTimeDefaultsToOperationalWindow() {
        OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 7, 20, 1, 30), null, null, java.time.LocalTime.of(1, 0));

        assertEquals(LocalDateTime.of(2026, 7, 20, 1, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 7, 21, 1, 0), range.getEnd());
    }

    @Test
    void explicitRangeOverridesDefaults() {
        OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 7, 20, 15, 0),
                "2026-07-01 10:20:30", "2026-07-03");

        assertEquals(LocalDateTime.of(2026, 7, 1, 10, 20, 30), range.getStart());
        assertEquals(LocalDateTime.of(2026, 7, 4, 4, 0), range.getEnd());
        assertEquals(true, range.isEndPureDate());

        OrderListTimeRangeResolver.Range explicitEnd = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 7, 20, 15, 0),
                "2026-07-01 10:20:30", "2026-07-03 23:59:59");
        assertEquals(LocalDateTime.of(2026, 7, 3, 23, 59, 59), explicitEnd.getEnd());
        assertEquals(false, explicitEnd.isEndPureDate());
    }

    @Test
    void explicitStartDefaultsEndToNow() {
        OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 7, 20, 15, 30),
                "2026-07-20 08:00:00", null);

        assertEquals(LocalDateTime.of(2026, 7, 20, 8, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 7, 20, 15, 30), range.getEnd());
    }

    @Test
    void supportsSlashDateFormatWithSettleTimeAutoCompletion() {
        // 默认日结时间 04:00
        OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 10, 25, 12, 0),
                "2026/10/25", "2026/10/25");

        assertEquals(LocalDateTime.of(2026, 10, 25, 4, 0, 0), range.getStart());
        assertEquals(LocalDateTime.of(2026, 10, 26, 4, 0, 0), range.getEnd());
        assertEquals(true, range.isEndPureDate());

        // 指定门店日结时间 05:00
        OrderListTimeRangeResolver.Range rangeShop5 = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 10, 25, 12, 0),
                "2026/10/24", "2026/10/24", java.time.LocalTime.of(5, 0));

        assertEquals(LocalDateTime.of(2026, 10, 24, 5, 0, 0), rangeShop5.getStart());
        assertEquals(LocalDateTime.of(2026, 10, 25, 5, 0, 0), rangeShop5.getEnd());

        LocalDateTime start = OrderListTimeRangeResolver.parseDateTime("2026/10/25", true);
        LocalDateTime end = OrderListTimeRangeResolver.parseDateTime("2026/10/25", false);
        assertEquals(LocalDateTime.of(2026, 10, 25, 4, 0, 0), start);
        assertEquals(LocalDateTime.of(2026, 10, 26, 4, 0, 0), end);
    }

    @Test
    void supportsVariousDateSeparators() {
        OrderListTimeRangeResolver.Range dotRange = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 10, 25, 12, 0),
                "2026.10.24", "2026.10.24");
        assertEquals(LocalDateTime.of(2026, 10, 24, 4, 0, 0), dotRange.getStart());
        assertEquals(LocalDateTime.of(2026, 10, 25, 4, 0, 0), dotRange.getEnd());

        OrderListTimeRangeResolver.Range compactRange = OrderListTimeRangeResolver.resolve(
                LocalDateTime.of(2026, 10, 25, 12, 0),
                "20261024", "20261024");
        assertEquals(LocalDateTime.of(2026, 10, 24, 4, 0, 0), compactRange.getStart());
        assertEquals(LocalDateTime.of(2026, 10, 25, 4, 0, 0), compactRange.getEnd());
    }

    @Test
    void rejectsEndBeforeStartForPureDates() {
        org.junit.jupiter.api.Assertions.assertThrows(IllegalArgumentException.class, () -> {
            OrderListTimeRangeResolver.resolve(
                    LocalDateTime.of(2026, 10, 25, 12, 0),
                    "2026/10/25", "2026/10/24");
        });
    }
}
