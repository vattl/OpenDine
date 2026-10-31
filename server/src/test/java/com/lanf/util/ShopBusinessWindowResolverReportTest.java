package com.lanf.util;

import com.lanf.entity.Shop;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.util.Date;
import java.util.TimeZone;

import static org.junit.jupiter.api.Assertions.*;

class ShopBusinessWindowResolverReportTest {

    @Test
    @DisplayName("快捷纯日期（今日、昨日、近7天、近30天）：后端根据门店 settle_time 自动补全为营业日区间")
    void pureDateAutoCompletesWithSettleTime() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        // 今日：2026-10-08 ~ 2026-10-08
        String[] today = ShopBusinessWindowResolver.resolveReportWindowText(shop, "2026-10-08", "2026-10-08");
        assertEquals("2026-10-08 04:00:00", today[0]);
        assertEquals("2026-10-09 04:00:00", today[1]);

        // 昨日：2026-10-07 ~ 2026-10-07
        String[] yesterday = ShopBusinessWindowResolver.resolveReportWindowText(shop, "2026-10-07", "2026-10-07");
        assertEquals("2026-10-07 04:00:00", yesterday[0]);
        assertEquals("2026-10-08 04:00:00", yesterday[1]);

        // 近7天：2026-10-02 ~ 2026-10-08
        String[] last7Days = ShopBusinessWindowResolver.resolveReportWindowText(shop, "2026-10-02", "2026-10-08");
        assertEquals("2026-10-02 04:00:00", last7Days[0]);
        assertEquals("2026-10-09 04:00:00", last7Days[1]);

        // 近30天：2026-09-09 ~ 2026-10-08
        String[] last30Days = ShopBusinessWindowResolver.resolveReportWindowText(shop, "2026-09-09", "2026-10-08");
        assertEquals("2026-09-09 04:00:00", last30Days[0]);
        assertEquals("2026-10-09 04:00:00", last30Days[1]);
    }

    @Test
    @DisplayName("未配置 settle_time 或 shop 为 null 时安全默认使用 04:00")
    void pureDateDefaultSettleTimeFallback() {
        // shop 为 null
        String[] win1 = ShopBusinessWindowResolver.resolveReportWindowText(null, "2026-10-08", "2026-10-08");
        assertEquals("2026-10-08 04:00:00", win1[0]);
        assertEquals("2026-10-09 04:00:00", win1[1]);

        // shop 未配置 settle_time
        Shop emptyShop = new Shop();
        String[] win2 = ShopBusinessWindowResolver.resolveReportWindowText(emptyShop, "2026-10-08", "2026-10-08");
        assertEquals("2026-10-08 04:00:00", win2[0]);
        assertEquals("2026-10-09 04:00:00", win2[1]);
    }

    @Test
    @DisplayName("门店配置自定义结算时间（例如 05:30）")
    void customShopSettleTime() {
        Shop shop = new Shop();
        shop.setSettle_time("05:30");

        String[] win = ShopBusinessWindowResolver.resolveReportWindowText(shop, "2026-10-08", "2026-10-08");
        assertEquals("2026-10-08 05:30:00", win[0]);
        assertEquals("2026-10-09 05:30:00", win[1]);
    }

    @Test
    @DisplayName("自定义时间筛选（带时分秒）：精确保留时分秒，不被营业日规则覆盖")
    void customTimePreservesHoursMinutesSeconds() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        // 标准 yyyy-MM-dd HH:mm:ss
        String[] win1 = ShopBusinessWindowResolver.resolveReportWindowText(
                shop, "2026-10-08 10:00:00", "2026-10-08 22:30:00");
        assertEquals("2026-10-08 10:00:00", win1[0]);
        assertEquals("2026-10-08 22:30:00", win1[1]);

        // 带 T 的 ISO 格式
        String[] win2 = ShopBusinessWindowResolver.resolveReportWindowText(
                shop, "2026-10-08T09:15:00", "2026-10-08T18:45:00");
        assertEquals("2026-10-08 09:15:00", win2[0]);
        assertEquals("2026-10-08 18:45:00", win2[1]);

        // 省略秒的 yyyy-MM-dd HH:mm 自动补齐 :00
        String[] win3 = ShopBusinessWindowResolver.resolveReportWindowText(
                shop, "2026-10-08 10:00", "2026-10-08 22:00");
        assertEquals("2026-10-08 10:00:00", win3[0]);
        assertEquals("2026-10-08 22:00:00", win3[1]);
    }

    @Test
    @DisplayName("单端纯日期传参自动补全为单日营业班次")
    void singleEndPureDate() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        // 仅传 start
        String[] winStartOnly = ShopBusinessWindowResolver.resolveReportWindowText(shop, "2026-10-08", null);
        assertEquals("2026-10-08 04:00:00", winStartOnly[0]);
        assertEquals("2026-10-09 04:00:00", winStartOnly[1]);

        // 仅传 end
        String[] winEndOnly = ShopBusinessWindowResolver.resolveReportWindowText(shop, null, "2026-10-08");
        assertEquals("2026-10-08 04:00:00", winEndOnly[0]);
        assertEquals("2026-10-09 04:00:00", winEndOnly[1]);
    }

    @Test
    @DisplayName("parseReportDate 兼容纯日期与带时分秒字符串截取")
    void parseReportDateCompatibility() {
        assertEquals(LocalDate.of(2026, 10, 8), ShopBusinessWindowResolver.parseReportDate("2026-10-08"));
        assertEquals(LocalDate.of(2026, 10, 8), ShopBusinessWindowResolver.parseReportDate("2026-10-08 14:20:00"));
        assertEquals(LocalDate.of(2026, 10, 8), ShopBusinessWindowResolver.parseReportDate("2026-10-08T14:20:00"));
        assertNull(ShopBusinessWindowResolver.parseReportDate(""));
        assertNull(ShopBusinessWindowResolver.parseReportDate(null));
    }

    @Test
    @DisplayName("resolveReportWindow 返回精确 Date 数组")
    void resolveReportWindowReturnsDates() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");

        Date[] dates = ShopBusinessWindowResolver.resolveReportWindow(shop, "2026-10-08", "2026-10-08");
        assertNotNull(dates);
        assertEquals(2, dates.length);

        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        sdf.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        assertEquals("2026-10-08 04:00:00", sdf.format(dates[0]));
        assertEquals("2026-10-09 04:00:00", sdf.format(dates[1]));
    }
}
