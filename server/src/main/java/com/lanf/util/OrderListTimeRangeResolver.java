package com.lanf.util;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;

import java.time.LocalTime;

/** Resolves the admin order list range; defaults to current operational business day [D settle_time, D+1 settle_time). */
public final class OrderListTimeRangeResolver {

    private static final DateTimeFormatter SECOND = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final DateTimeFormatter MINUTE = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    private OrderListTimeRangeResolver() {
    }

    public static Range resolve(LocalDateTime now, String startText, String endText) {
        return resolve(now, startText, endText, ShopBusinessWindowResolver.DEFAULT_SETTLE_TIME);
    }

    public static Range resolve(LocalDateTime now, String startText, String endText, LocalTime settleTime) {
        if (now == null) {
            throw new IllegalArgumentException("now cannot be null");
        }
        LocalTime settle = settleTime != null ? settleTime : ShopBusinessWindowResolver.DEFAULT_SETTLE_TIME;

        boolean startIsPure = isPureDate(startText);
        boolean endIsPure = isPureDate(endText);
        LocalDate startDate = startIsPure ? parsePureDate(startText) : null;
        LocalDate endDate = endIsPure ? parsePureDate(endText) : null;

        if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
            throw new IllegalArgumentException("endTime cannot be earlier than startTime");
        }

        LocalDateTime start = parse(startText, true, settle);
        LocalDateTime end = parse(endText, false, settle);

        if (start == null && end == null) {
            LocalDate d = now.toLocalTime().isBefore(settle) ? now.toLocalDate().minusDays(1) : now.toLocalDate();
            start = LocalDateTime.of(d, settle);
            end = LocalDateTime.of(d.plusDays(1), settle);
            endIsPure = true;
        } else {
            if (start == null) {
                LocalDate d = end.toLocalTime().isBefore(settle) ? end.toLocalDate().minusDays(1) : end.toLocalDate();
                start = LocalDateTime.of(d, settle);
            }
            if (end == null) {
                end = now;
            }
        }
        if (end.isBefore(start)) {
            throw new IllegalArgumentException("endTime cannot be earlier than startTime");
        }
        return new Range(start, end, endIsPure);
    }

    public static String format(LocalDateTime value) {
        return value != null ? value.format(SECOND) : null;
    }

    public static LocalDateTime parseDateTime(String value, boolean isStart) {
        return parse(value, isStart, ShopBusinessWindowResolver.DEFAULT_SETTLE_TIME);
    }

    public static LocalDateTime parseDateTime(String value, boolean isStart, LocalTime settleTime) {
        return parse(value, isStart, settleTime);
    }

    public static boolean isPureDate(String value) {
        return parsePureDate(value) != null;
    }

    public static LocalDate parsePureDate(String value) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        String s = normalizeText(value);
        if (s.matches("^\\d{4}-\\d{1,2}-\\d{1,2}$")) {
            String[] parts = s.split("-");
            try {
                int y = Integer.parseInt(parts[0]);
                int m = Integer.parseInt(parts[1]);
                int d = Integer.parseInt(parts[2]);
                return LocalDate.of(y, m, d);
            } catch (Exception e) {
                return null;
            }
        }
        if (s.matches("^\\d{8}$")) {
            try {
                int y = Integer.parseInt(s.substring(0, 4));
                int m = Integer.parseInt(s.substring(4, 6));
                int d = Integer.parseInt(s.substring(6, 8));
                return LocalDate.of(y, m, d);
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }

    public static String normalizeText(String value) {
        if (value == null) {
            return null;
        }
        String s = value.trim();
        s = s.replace("%2F", "/").replace("%2f", "/").replace("%20", " ");
        s = s.replace('T', ' ').replace('/', '-').replace('.', '-');
        s = s.replaceAll("\\s+", " ");
        return s;
    }

    private static LocalDateTime parse(String value, boolean isStart, LocalTime settleTime) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        String text = normalizeText(value);
        try {
            return LocalDateTime.parse(text, SECOND);
        } catch (DateTimeParseException ignored) {
        }
        try {
            return LocalDateTime.parse(text, MINUTE);
        } catch (DateTimeParseException ignored) {
        }
        LocalDate date = parsePureDate(text);
        if (date != null) {
            LocalTime settle = settleTime != null ? settleTime : ShopBusinessWindowResolver.DEFAULT_SETTLE_TIME;
            return isStart ? LocalDateTime.of(date, settle) : LocalDateTime.of(date.plusDays(1), settle);
        }
        throw new IllegalArgumentException("Invalid time format: " + value);
    }

    public static final class Range {
        private final LocalDateTime start;
        private final LocalDateTime end;
        private final boolean endPureDate;

        public Range(LocalDateTime start, LocalDateTime end) {
            this(start, end, false);
        }

        public Range(LocalDateTime start, LocalDateTime end, boolean endPureDate) {
            this.start = start;
            this.end = end;
            this.endPureDate = endPureDate;
        }

        public LocalDateTime getStart() {
            return start;
        }

        public LocalDateTime getEnd() {
            return end;
        }

        public boolean isEndPureDate() {
            return endPureDate;
        }
    }
}
