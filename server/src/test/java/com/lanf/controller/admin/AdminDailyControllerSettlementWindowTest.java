package com.lanf.controller.admin;

import com.lanf.entity.Shop;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

class AdminDailyControllerSettlementWindowTest {

    @Test
    void dailySettlementUsesTheActiveShiftAfterOpening() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        LocalDate settlementDay = AdminDailyController.resolveSettlementDay(
                shop, null, LocalDateTime.of(2026, 9, 10, 18, 30));

        assertEquals(LocalDate.of(2026, 9, 10), settlementDay);
    }

    @Test
    void dailySettlementKeepsTheActiveOvernightShiftBeforeSettlement() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        LocalDate settlementDay = AdminDailyController.resolveSettlementDay(
                shop, "", LocalDateTime.of(2026, 9, 11, 2, 0));

        assertEquals(LocalDate.of(2026, 9, 10), settlementDay);
    }

    @Test
    void dailySettlementUsesTheLatestCompletedShiftWhileClosed() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        LocalDate settlementDay = AdminDailyController.currentSettlementDay(
                shop, LocalDateTime.of(2026, 9, 11, 10, 0));

        assertEquals(LocalDate.of(2026, 9, 11), settlementDay);
    }

    @Test
    void explicitSettlementDateStillSelectsHistoricalData() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        LocalDate settlementDay = AdminDailyController.resolveSettlementDay(
                shop, "2026-09-08", LocalDateTime.of(2026, 9, 11, 18, 30));

        assertEquals(LocalDate.of(2026, 9, 8), settlementDay);
    }
}
