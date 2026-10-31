package com.lanf.controller.admin;

import com.lanf.entity.Shop;
import com.lanf.util.ShopBusinessWindowResolver;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;

class AdminReportControllerSettlementWindowTest {

    @Test
    @DisplayName("实时看板营业班次：settle_time=05:00 时 16:00、03:00、06:00 班次推算与 24h 实时窗口")
    void dashboardRealtimeOperationalWindowCases() {
        Shop shop = new Shop();
        shop.setSettle_time("05:00");

        // 1. 9.11 16:00 查询 -> 9.11 班次，窗口 9.11 05:00:00 - 9.12 05:00:00
        LocalDate day1 = AdminReportController.dashboardSettlementDay(shop, LocalDateTime.of(2026, 9, 11, 16, 0));
        assertEquals(LocalDate.of(2026, 9, 11), day1);
        String[] win1 = ShopBusinessWindowResolver.operationalWindowText(shop, day1);
        assertArrayEquals(new String[]{"2026-09-11 05:00:00", "2026-09-12 05:00:00"}, win1);
        assertArrayEquals(win1, ShopBusinessWindowResolver.resolveOperationalWindowText(shop, day1.toString()));

        // 2. 9.12 03:00 查询 -> 仍属于 9.11 班次，窗口 9.11 05:00:00 - 9.12 05:00:00
        LocalDate day2 = AdminReportController.dashboardSettlementDay(shop, LocalDateTime.of(2026, 9, 12, 3, 0));
        assertEquals(LocalDate.of(2026, 9, 11), day2);
        String[] win2 = ShopBusinessWindowResolver.operationalWindowText(shop, day2);
        assertArrayEquals(new String[]{"2026-09-11 05:00:00", "2026-09-12 05:00:00"}, win2);
        assertArrayEquals(win2, ShopBusinessWindowResolver.resolveOperationalWindowText(shop, day2.toString()));

        // 3. 9.12 06:00 查询 -> 进入 9.12 班次，窗口 9.12 05:00:00 - 9.13 05:00:00
        LocalDate day3 = AdminReportController.dashboardSettlementDay(shop, LocalDateTime.of(2026, 9, 12, 6, 0));
        assertEquals(LocalDate.of(2026, 9, 12), day3);
        String[] win3 = ShopBusinessWindowResolver.operationalWindowText(shop, day3);
        assertArrayEquals(new String[]{"2026-09-12 05:00:00", "2026-09-13 05:00:00"}, win3);
        assertArrayEquals(win3, ShopBusinessWindowResolver.resolveOperationalWindowText(shop, day3.toString()));
    }

    @Test
    void dashboardUsesTheActiveShiftAfterItsSettlementWindowStarts() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        LocalDate settlementDay = AdminReportController.dashboardSettlementDay(
                shop, LocalDateTime.of(2026, 9, 10, 18, 30));

        assertEquals(LocalDate.of(2026, 9, 10), settlementDay);
    }

    @Test
    void dashboardKeepsTheLatestCompletedShiftDuringTheClosedGap() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        LocalDate settlementDay = AdminReportController.dashboardSettlementDay(
                shop, LocalDateTime.of(2026, 9, 10, 3, 0));

        assertEquals(LocalDate.of(2026, 9, 9), settlementDay);
    }
}
