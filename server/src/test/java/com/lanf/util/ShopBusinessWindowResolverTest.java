package com.lanf.util;

import com.lanf.common.ApiException;
import com.lanf.entity.Shop;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Date;
import java.util.TimeZone;

import static org.junit.jupiter.api.Assertions.*;

@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class ShopBusinessWindowResolverTest {
    private static final DateTimeFormatter TEXT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @Test
    @Order(1)
    @DisplayName("营业日窗口固定使用 Asia/Shanghai，不受服务器默认时区影响")
    void businessWindowUsesShanghaiTimezoneInsteadOfJvmDefault() {
        TimeZone original = TimeZone.getDefault();
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
            Shop shop = new Shop();
            shop.setSettle_time("04:00");

            Date[] window = ShopBusinessWindowResolver.settlementWindowFor(
                    shop, LocalDate.of(2026, 10, 2));

            assertEquals("2026-10-01T20:00:00Z", window[0].toInstant().toString());
            assertEquals("2026-10-02T20:00:00Z", window[1].toInstant().toString());
        } finally {
            TimeZone.setDefault(original);
        }
    }

    @Test
    @DisplayName("严格校验：未配置 settle_time 时直接抛出 ApiException，无兜底")
    void requireSettleTimeThrowsExceptionWhenNotConfigured() {
        // 1. shop 为 null
        ApiException ex1 = assertThrows(ApiException.class, () -> ShopBusinessWindowResolver.requireSettleTime(null));
        assertEquals("SETTLE_TIME_NOT_CONFIGURED", ex1.getErrorCode());

        // 2. settle_time 为 null
        Shop shopNoSettle = new Shop();
        shopNoSettle.setClose_time("03:00");
        ApiException ex2 = assertThrows(ApiException.class, () -> ShopBusinessWindowResolver.requireSettleTime(shopNoSettle));
        assertEquals("SETTLE_TIME_NOT_CONFIGURED", ex2.getErrorCode());

        // 3. settle_time 为空白字符串
        shopNoSettle.setSettle_time("   ");
        ApiException ex3 = assertThrows(ApiException.class, () -> ShopBusinessWindowResolver.requireSettleTime(shopNoSettle));
        assertEquals("SETTLE_TIME_NOT_CONFIGURED", ex3.getErrorCode());

        // 4. settle_time 格式非法
        shopNoSettle.setSettle_time("invalid");
        ApiException ex4 = assertThrows(ApiException.class, () -> ShopBusinessWindowResolver.requireSettleTime(shopNoSettle));
        assertEquals("SETTLE_TIME_INVALID", ex4.getErrorCode());
    }

    @Test
    @DisplayName("实时数据接口：时间范围为当前活动营业班次的 24 小时窗口 [D settle, D+1 settle)")
    void realtimeOperationalWindowCalculation() {
        Shop shop = new Shop();
        shop.setSettle_time("05:00");

        // 1. 9.11 16:00 查询 -> 9.11 05:00 - 9.12 05:00
        LocalDateTime t1 = LocalDateTime.of(2026, 9, 11, 16, 0, 0);
        Date[] win1 = ShopBusinessWindowResolver.operationalWindow(shop, t1);
        assertEquals("2026-09-11 05:00:00", text(win1[0]));
        assertEquals("2026-09-12 05:00:00", text(win1[1]));

        // 2. 9.12 03:00 查询 -> 仍是 9.11 05:00 - 9.12 05:00
        LocalDateTime t2 = LocalDateTime.of(2026, 9, 12, 3, 0, 0);
        Date[] win2 = ShopBusinessWindowResolver.operationalWindow(shop, t2);
        assertEquals("2026-09-11 05:00:00", text(win2[0]));
        assertEquals("2026-09-12 05:00:00", text(win2[1]));

        // 3. 9.12 06:00 查询 -> 进入新班次 9.12 05:00 - 9.13 05:00
        LocalDateTime t3 = LocalDateTime.of(2026, 9, 12, 6, 0, 0);
        Date[] win3 = ShopBusinessWindowResolver.operationalWindow(shop, t3);
        assertEquals("2026-09-12 05:00:00", text(win3[0]));
        assertEquals("2026-09-13 05:00:00", text(win3[1]));
    }

    @Test
    @DisplayName("已结算数据接口：默认时间范围为最近已完成的 24 小时结算周期 [D-1 settle, D settle)")
    void settledReportingWindowCalculation() {
        Shop shop = new Shop();
        shop.setSettle_time("05:00");

        // 1. 9.11 16:00 查询 (未传 date) -> 9.10 05:00 - 9.11 05:00
        LocalDateTime t1 = LocalDateTime.of(2026, 9, 11, 16, 0, 0);
        LocalDate comp1 = ShopBusinessWindowResolver.completedSettlementDay(shop, t1);
        Date[] win1 = ShopBusinessWindowResolver.settlementWindowFor(shop, comp1);
        assertEquals("2026-09-10 05:00:00", text(win1[0]));
        assertEquals("2026-09-11 05:00:00", text(win1[1]));

        // 2. 9.12 03:00 查询 (未传 date) -> 9.10 05:00 - 9.11 05:00
        LocalDateTime t2 = LocalDateTime.of(2026, 9, 12, 3, 0, 0);
        LocalDate comp2 = ShopBusinessWindowResolver.completedSettlementDay(shop, t2);
        Date[] win2 = ShopBusinessWindowResolver.settlementWindowFor(shop, comp2);
        assertEquals("2026-09-10 05:00:00", text(win2[0]));
        assertEquals("2026-09-11 05:00:00", text(win2[1]));

        // 3. 9.12 06:00 查询 (未传 date) -> 9.11 05:00 - 9.12 05:00
        LocalDateTime t3 = LocalDateTime.of(2026, 9, 12, 6, 0, 0);
        LocalDate comp3 = ShopBusinessWindowResolver.completedSettlementDay(shop, t3);
        Date[] win3 = ShopBusinessWindowResolver.settlementWindowFor(shop, comp3);
        assertEquals("2026-09-11 05:00:00", text(win3[0]));
        assertEquals("2026-09-12 05:00:00", text(win3[1]));
    }

    @Test
    @DisplayName("已结算报表：指定营业日及区间查询 [startDate settle, endDate+1 settle)")
    void settledReportingRangeCalculation() {
        Shop shop = new Shop();
        shop.setSettle_time("05:00");

        // 指定单营业日 2026-09-11 -> [2026-09-11 05:00, 2026-09-12 05:00)
        Date[] win = ShopBusinessWindowResolver.settlementWindowFor(shop, LocalDate.of(2026, 9, 11));
        assertEquals("2026-09-11 05:00:00", text(win[0]));
        assertEquals("2026-09-12 05:00:00", text(win[1]));

        // 指定周报区间 [2026-09-01, 2026-09-07] -> [2026-09-01 05:00, 2026-09-08 05:00)
        Date[] rangeWin = ShopBusinessWindowResolver.settlementWindowRange(shop,
                LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 7));
        assertEquals("2026-09-01 05:00:00", text(rangeWin[0]));
        assertEquals("2026-09-08 05:00:00", text(rangeWin[1]));
    }

    @Test
    @DisplayName("安全兜底：未配置 settle_time 时 resolveSettleTimeOrDefault 兜底为 04:00")
    void fallbackSettleTime() {
        Shop shop = new Shop();
        assertEquals(java.time.LocalTime.of(4, 0), ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop));
        assertEquals(java.time.LocalTime.of(4, 0), ShopBusinessWindowResolver.resolveSettleTimeOrDefault(null));
    }

    @Test
    @DisplayName("自然日辅助规则：[day 00:00:00, day+1 00:00:00)")
    void naturalDayWindowCalculation() {
        Date[] nat = ShopBusinessWindowResolver.naturalDayWindowFor(LocalDate.of(2026, 9, 11));
        assertEquals("2026-09-11 00:00:00", text(nat[0]));
        assertEquals("2026-09-12 00:00:00", text(nat[1]));

        Date[] natRange = ShopBusinessWindowResolver.naturalDayRange(
                LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 7));
        assertEquals("2026-09-01 00:00:00", text(natRange[0]));
        assertEquals("2026-09-08 00:00:00", text(natRange[1]));
    }

    @Test
    @DisplayName("营业时段判定：非跨天时段（10:00 ~ 22:00）")
    void isWithinBusinessHours_nonOvernight() {
        Shop shop = new Shop();
        shop.setOpen_time("10:00");
        shop.setClose_time("22:00");

        LocalDate today = LocalDate.of(2026, 10, 29);

        // 开门前：09:59 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(9, 59))));
        // 开门时刻：10:00 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(10, 0))));
        // 午市营业中：12:30 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(12, 30))));
        // 晚市营业中：21:59 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(21, 59))));
        // 打烊时刻：22:00 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(22, 0))));
        // 打烊后夜间：23:30 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(23, 30))));
    }

    @Test
    @DisplayName("营业时段判定：跨天营业时段（16:00 ~ 次日 02:00）")
    void isWithinBusinessHours_overnight() {
        Shop shop = new Shop();
        shop.setOpen_time("16:00");
        shop.setClose_time("02:00");

        LocalDate today = LocalDate.of(2026, 10, 29);

        // 下午开门前：15:59 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(15, 59))));
        // 开门时刻：16:00 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(16, 0))));
        // 夜间就餐高峰：20:00 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(20, 0))));
        // 午夜跨天前：23:59 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(23, 59))));
        // 跨天凌晨就餐中：01:30 -> 是
        assertTrue(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(1, 30))));
        // 打烊时刻：02:00 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(2, 0))));
        // 清晨结算时段：03:30 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(3, 30))));
        // 上午休息时段：10:00 -> 否
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(10, 0))));
    }

    @Test
    @DisplayName("营业时段判定：未配置 open_time / close_time 时不启用时钟阻断")
    void isWithinBusinessHours_emptyConfig() {
        Shop shop = new Shop();
        LocalDate today = LocalDate.of(2026, 10, 29);
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(shop, LocalDateTime.of(today, java.time.LocalTime.of(12, 0))));
        assertFalse(ShopBusinessWindowResolver.isWithinBusinessHours(null, LocalDateTime.of(today, java.time.LocalTime.of(12, 0))));
    }

    private static String text(Date value) {
        return value.toInstant().atZone(ZoneId.systemDefault()).format(TEXT);
    }
}
