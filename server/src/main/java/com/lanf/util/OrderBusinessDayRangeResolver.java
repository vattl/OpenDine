package com.lanf.util;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * @deprecated 硬编码 16:00～次日 04:00 的营业日解析（不感知门店 open_time/settle_time 配置）；
 * 请改用 {@link ShopBusinessWindowResolver}（营业日 D = [D 的 open_time, D+1 的 settle_time)，门店配置优先）。
 * 本类仅因既有测试引用而保留，不再新增使用方。
 */
@Deprecated
public final class OrderBusinessDayRangeResolver {

    private static final int BUSINESS_START_HOUR = 16;
    private static final int BUSINESS_END_HOUR = 4;

    private OrderBusinessDayRangeResolver() {
    }

    public static Range resolve(LocalDateTime now) {
        if (now == null) {
            throw new IllegalArgumentException("now cannot be null");
        }
        LocalDate startDate = now.getHour() >= BUSINESS_START_HOUR
                ? now.toLocalDate()
                : now.toLocalDate().minusDays(1);
        LocalDateTime start = startDate.atTime(BUSINESS_START_HOUR, 0);
        LocalDateTime end = startDate.plusDays(1).atTime(BUSINESS_END_HOUR, 0);
        return new Range(start, end);
    }

    public static final class Range {
        private final LocalDateTime start;
        private final LocalDateTime end;

        private Range(LocalDateTime start, LocalDateTime end) {
            this.start = start;
            this.end = end;
        }

        public LocalDateTime getStart() {
            return start;
        }

        public LocalDateTime getEnd() {
            return end;
        }
    }
}
