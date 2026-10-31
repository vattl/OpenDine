package com.lanf.util;

import com.lanf.common.ApiException;
import com.lanf.entity.Shop;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.Date;

/**
 * 统一数据接口时间窗口解析器。
 *
 * <p>【业务规则】
 * 1. 严格校验：必须配置 {@code t_shop.settle_time}，未配置时直接抛出 {@link ApiException} 提示错误，不进行默认兜底。
 * 2. 实时数据接口（当天营业额、今日订单数、实时未结金额、当前日结班次预览、收银端今日订单等）：
 *    - 时间窗口为当前营业班次的完整 24 小时周期：{@code [班次起始日 settle_time, 班次起始日+1天 settle_time)}。
 *    - 示例（settle_time = 05:00）：
 *      - 9.11 16:00 查询 → [9.11 05:00, 9.12 05:00)
 *      - 9.12 03:00 查询 → [9.11 05:00, 9.12 05:00)
 *      - 9.12 06:00 查询 → [9.12 05:00, 9.13 05:00)
 * 3. 已结算数据接口（日报、周报、月报、历史营业额、菜品排行、收银绩效、Analytics 默认报表等）：
 *    - 未指定日期时取最近已完成的完整 24 小时营业日；显式日期 D 始终表示营业日起始日期。
 *    - 示例（settle_time = 05:00，未传 date 时）：
 *      - 9.11 16:00 查询 → [9.10 05:00, 9.11 05:00)
 *      - 9.12 03:00 查询 → [9.10 05:00, 9.11 05:00)
 *      - 9.12 06:00 查询 → [9.11 05:00, 9.12 05:00)
 *    - 指定结算日 D 或区间 [D_start, D_end] 时：
 *      - 单日 D → [D日 settle_time, D+1日 settle_time)
 *      - 区间 [D_start, D_end] → [D_start日 settle_time, D_end+1日 settle_time)
 * 4. 自然日次要规则：保留自然日 [00:00:00, 23:59:59] 维度的计算能力。
 * </p>
 */
public final class ShopBusinessWindowResolver {

    /** 门店业务目前统一按中国标准时间结算，不依赖部署主机的默认时区。 */
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private ShopBusinessWindowResolver() {
    }

    public static final LocalTime DEFAULT_SETTLE_TIME = LocalTime.of(4, 0);

    /**
     * 严格校验并解析门店 settle_time（HH:mm）。
     * 若未配置或为空，直接抛出 ApiException(400, "SETTLE_TIME_NOT_CONFIGURED")，无兜底。
     */
    public static LocalTime requireSettleTime(Shop shop) {
        if (shop == null || shop.getSettle_time() == null || shop.getSettle_time().trim().isEmpty()) {
            throw new ApiException(400, "SETTLE_TIME_NOT_CONFIGURED", "门店未设置结算时间(settle_time)，无法计算数据窗口");
        }
        LocalTime settle = parse(shop.getSettle_time());
        if (settle == null) {
            throw new ApiException(400, "SETTLE_TIME_INVALID", "门店结算时间格式错误，应为 HH:mm");
        }
        return settle;
    }

    /**
     * 解析门店 settle_time，未配置时安全兜底为默认分界点 04:00。
     */
    public static LocalTime resolveSettleTimeOrDefault(Shop shop) {
        if (shop == null || shop.getSettle_time() == null || shop.getSettle_time().trim().isEmpty()) {
            return DEFAULT_SETTLE_TIME;
        }
        LocalTime settle = parse(shop.getSettle_time());
        return settle != null ? settle : DEFAULT_SETTLE_TIME;
    }

    // ==========================================
    // 1. 实时数据窗口（Real-time / Operational）
    // ==========================================

    /**
     * 计算当前活动营业班次的起始日期。
     * 当前时刻在 settle_time 之前归属前一日班次，当前时刻在 settle_time 之后归属今日班次。
     */
    public static LocalDate operationalBusinessDay(Shop shop, LocalDateTime now) {
        LocalTime settle = requireSettleTime(shop);
        return now.toLocalTime().isBefore(settle) ? now.toLocalDate().minusDays(1) : now.toLocalDate();
    }

    public static LocalDate operationalBusinessDay(Shop shop) {
        return operationalBusinessDay(shop, LocalDateTime.now());
    }

    /**
     * 指定营业班次起始日的实时数据 24 小时窗口：{@code [D settle_time, D+1 settle_time)}。
     */
    public static Date[] operationalWindowFor(Shop shop, LocalDate operationalBusinessDay) {
        LocalTime settle = requireSettleTime(shop);
        LocalDateTime start = LocalDateTime.of(operationalBusinessDay, settle);
        LocalDateTime end = LocalDateTime.of(operationalBusinessDay.plusDays(1), settle);
        return new Date[]{Date.from(start.atZone(ZONE).toInstant()), Date.from(end.atZone(ZONE).toInstant())};
    }

    /**
     * 当前活动营业班次的实时数据 24 小时窗口：{@code [当前班次起始日 settle_time, 当前班次起始日+1 settle_time)}。
     */
    public static Date[] operationalWindow(Shop shop, LocalDateTime now) {
        LocalDate day = operationalBusinessDay(shop, now);
        return operationalWindowFor(shop, day);
    }

    public static Date[] operationalWindow(Shop shop) {
        return operationalWindow(shop, LocalDateTime.now());
    }

    public static String[] operationalWindowText(Shop shop, LocalDate operationalBusinessDay) {
        Date[] win = operationalWindowFor(shop, operationalBusinessDay);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    public static String[] operationalWindowText(Shop shop) {
        Date[] win = operationalWindow(shop);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    /**
     * 解析实时数据窗口（支持传入 date 参数为指定营业班次起始日）。
     */
    public static Date[] resolveOperationalWindow(Shop shop, String dateParam) {
        if (dateParam != null && !dateParam.trim().isEmpty()) {
            try {
                String s = dateParam.trim().replace('/', '-').replace('.', '-');
                if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
                    s = s.substring(0, 10);
                }
                LocalDate day = LocalDate.parse(s);
                return operationalWindowFor(shop, day);
            } catch (DateTimeParseException e) {
                throw new IllegalArgumentException("日期格式错误，应为 yyyy-MM-dd: " + dateParam);
            }
        }
        return operationalWindow(shop);
    }

    public static String[] resolveOperationalWindowText(Shop shop, String dateParam) {
        Date[] win = resolveOperationalWindow(shop, dateParam);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    // ==========================================
    // 2. 已结算数据窗口（Settled / Reporting）
    // ==========================================

    /**
     * 获取最近已完成的营业日。
     * 当前时刻在 settle_time 之前，最近完成的营业日为前两日（当前活动班次为前一日）；
     * 当前时刻在 settle_time 之后，最近完成的营业日为前一日（当前活动班次为今日）。
     * 即：completedSettlementDay = operationalBusinessDay(shop, now).minusDays(1)。
     */
    public static LocalDate completedSettlementDay(Shop shop, LocalDateTime now) {
        return operationalBusinessDay(shop, now).minusDays(1);
    }

    public static LocalDate completedSettlementDay(Shop shop) {
        return completedSettlementDay(shop, LocalDateTime.now());
    }

    /**
     * 指定营业日 D 的 24 小时窗口：{@code [D settle_time, D+1 settle_time)}。
     * 行业标准对齐：报表查询日期 D 即为账期起始日，覆盖该营业日的完整 24 小时经营周期。
     */
    public static Date[] settlementWindowFor(Shop shop, LocalDate settlementDay) {
        return operationalWindowFor(shop, settlementDay);
    }

    public static String[] settlementWindowText(Shop shop, LocalDate settlementDay) {
        Date[] win = settlementWindowFor(shop, settlementDay);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    /**
     * 解析结算日（若未传入则默认取最近已完成的结算日）。
     */
    public static LocalDate resolveSettlementDay(Shop shop, String settlementDateParam, LocalDateTime now) {
        if (settlementDateParam != null && !settlementDateParam.trim().isEmpty()) {
            try {
                String s = settlementDateParam.trim();
                if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
                    s = s.substring(0, 10);
                }
                return LocalDate.parse(s);
            } catch (DateTimeParseException e) {
                throw new IllegalArgumentException("日期格式错误，应为 yyyy-MM-dd: " + settlementDateParam);
            }
        }
        return completedSettlementDay(shop, now);
    }

    public static LocalDate resolveSettlementDay(Shop shop, String settlementDateParam) {
        return resolveSettlementDay(shop, settlementDateParam, LocalDateTime.now());
    }

    /**
     * 解析已结算报表时间窗口（未传 date 取最近已完成 24h 结算周期）。
     */
    public static Date[] resolveSettlementWindow(Shop shop, String settlementDateParam) {
        return settlementWindowFor(shop, resolveSettlementDay(shop, settlementDateParam, LocalDateTime.now()));
    }

    public static String[] resolveSettlementWindowText(Shop shop, String settlementDateParam) {
        Date[] win = resolveSettlementWindow(shop, settlementDateParam);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    /** 兼容历史调用方（指向已结算窗口解析）。 */
    public static Date[] resolveWindow(Shop shop, String settlementDateParam) {
        return resolveSettlementWindow(shop, settlementDateParam);
    }

    /**
     * 已结算报表日期区间 [startSettlementDay, endSettlementDay] 对应的完整连续结算窗口：
     * {@code [startSettlementDay settle_time, endSettlementDay+1 settle_time)}。
     */
    public static Date[] settlementWindowRange(Shop shop, LocalDate startSettlementDay, LocalDate endSettlementDay) {
        Date[] startWin = settlementWindowFor(shop, startSettlementDay);
        Date[] endWin = settlementWindowFor(shop, endSettlementDay);
        return new Date[]{startWin[0], endWin[1]};
    }

    public static String[] settlementWindowRangeText(Shop shop, LocalDate startSettlementDay, LocalDate endSettlementDay) {
        Date[] win = settlementWindowRange(shop, startSettlementDay, endSettlementDay);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    /**
     * 数据报表统一时间窗口解析（文本格式 [startTime, endTime]）。
     * 规则：
     * 1. 纯日期输入（yyyy-MM-dd，如今日、昨日、近7天、近30天等快捷档位）：
     *    - 起始时间：startDate settle_time（默认04:00:00），例如 "2026-10-08 04:00:00"；
     *    - 截止时间：(endDate + 1日) settle_time（默认04:00:00），例如 "2026-10-09 04:00:00"；
     * 2. 自定义输入且含时分秒（如 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd HH:mm）：
     *    - 精确保留客户端指定的时分秒，不进行营业日强制替换，仅做规范化（T 转为空格，缺失秒补 :00）；
     * 3. 缺省处理：
     *    - 两端皆未传：取最近已结算营业日完整 24h 周期；
     *    - 仅传 start 纯日期：end 默认与 start 相同（单日查询）；
     *    - 仅传 end 纯日期：start 默认与 end 相同（单日查询）；
     *    - 仅传一端自定义时间：另一端安全对齐。
     */
    public static String[] resolveReportWindowText(Shop shop, String startRaw, String endRaw) {
        LocalTime settle = resolveSettleTimeOrDefault(shop);
        String settleText = String.format("%02d:%02d:00", settle.getHour(), settle.getMinute());

        String start = startRaw != null ? startRaw.trim().replace('/', '-').replace('.', '-') : null;
        String end = endRaw != null ? endRaw.trim().replace('/', '-').replace('.', '-') : null;

        if ((start == null || start.isEmpty()) && (end == null || end.isEmpty())) {
            LocalDate compDay = completedSettlementDay(shop, LocalDateTime.now());
            return settlementWindowText(shop, compDay);
        }

        if ((start == null || start.isEmpty()) && isPureDate(end)) {
            start = end;
        } else if ((end == null || end.isEmpty()) && isPureDate(start)) {
            end = start;
        }

        String startTimeText;
        if (isPureDate(start)) {
            LocalDate startDate = LocalDate.parse(start);
            startTimeText = startDate.toString() + " " + settleText;
        } else if (start != null && !start.isEmpty()) {
            startTimeText = normalizeCustomTime(start);
        } else {
            LocalDate ed = parseReportDate(end);
            startTimeText = (ed != null ? ed.toString() : LocalDate.now().toString()) + " " + settleText;
        }

        String endTimeText;
        if (isPureDate(end)) {
            LocalDate endDate = LocalDate.parse(end);
            endTimeText = endDate.plusDays(1).toString() + " " + settleText;
        } else if (end != null && !end.isEmpty()) {
            endTimeText = normalizeCustomTime(end);
        } else {
            LocalDate sd = parseReportDate(start);
            endTimeText = (sd != null ? sd.plusDays(1).toString() : LocalDate.now().plusDays(1).toString()) + " " + settleText;
        }

        return new String[]{startTimeText, endTimeText};
    }

    /**
     * 数据报表统一时间窗口解析（Date 对象格式 [startTime, endTime]）。
     */
    public static Date[] resolveReportWindow(Shop shop, String startRaw, String endRaw) {
        String[] text = resolveReportWindowText(shop, startRaw, endRaw);
        try {
            java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
            sdf.setTimeZone(java.util.TimeZone.getTimeZone(ZONE));
            return new Date[]{sdf.parse(text[0]), sdf.parse(text[1])};
        } catch (Exception e) {
            throw new IllegalArgumentException("无法将报表时间解析为 Date: " + java.util.Arrays.toString(text), e);
        }
    }

    /**
     * 解析报表日期参数（支持纯日期 yyyy-MM-dd 或带时分秒字符串，统一截取有效日期）。
     */
    public static LocalDate parseReportDate(String dateParam) {
        if (dateParam == null || dateParam.trim().isEmpty()) {
            return null;
        }
        String s = dateParam.trim().replace('T', ' ').replace('/', '-').replace('.', '-');
        if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
            s = s.substring(0, 10);
        }
        return LocalDate.parse(s);
    }

    public static boolean isPureDate(String text) {
        if (text == null) {
            return false;
        }
        String s = text.trim().replace('/', '-').replace('.', '-');
        return s.matches("^\\d{4}-\\d{1,2}-\\d{1,2}$") || s.matches("^\\d{8}$");
    }

    public static String normalizeCustomTime(String text) {
        if (text == null || text.trim().isEmpty()) {
            return "";
        }
        String s = text.trim().replace('T', ' ');
        int dot = s.indexOf('.');
        if (dot > 0) {
            s = s.substring(0, dot);
        }
        if (s.matches("^\\d{4}-\\d{1,2}-\\d{1,2}\\s+\\d{1,2}:\\d{1,2}$")) {
            s = s + ":00";
        }
        return s;
    }

    public static Date[] settlementWindowRange(Shop shop, String startRaw, String endRaw) {
        return resolveReportWindow(shop, startRaw, endRaw);
    }

    // ==========================================
    // 3. 自然日辅助规则（Natural Day Secondary Rule）
    // ==========================================

    /**
     * 自然日时间窗口：{@code [day 00:00:00, day+1 00:00:00)}。
     */
    public static Date[] naturalDayWindowFor(LocalDate day) {
        LocalDateTime start = LocalDateTime.of(day, LocalTime.MIN);
        LocalDateTime end = LocalDateTime.of(day.plusDays(1), LocalTime.MIN);
        return new Date[]{Date.from(start.atZone(ZONE).toInstant()), Date.from(end.atZone(ZONE).toInstant())};
    }

    public static String[] naturalDayWindowText(LocalDate day) {
        Date[] win = naturalDayWindowFor(day);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    /**
     * 自然日区间：{@code [startDay 00:00:00, endDay+1 00:00:00)}。
     */
    public static Date[] naturalDayRange(LocalDate startDay, LocalDate endDay) {
        LocalDateTime start = LocalDateTime.of(startDay, LocalTime.MIN);
        LocalDateTime end = LocalDateTime.of(endDay.plusDays(1), LocalTime.MIN);
        return new Date[]{Date.from(start.atZone(ZONE).toInstant()), Date.from(end.atZone(ZONE).toInstant())};
    }

    public static String[] naturalDayRangeText(LocalDate startDay, LocalDate endDay) {
        Date[] win = naturalDayRange(startDay, endDay);
        return new String[]{toText(win[0]), toText(win[1])};
    }

    // ==========================================
    // 4. 兼容性方法
    // ==========================================

    /** @deprecated 推荐使用 {@link #operationalWindowFor(Shop, LocalDate)} 或 {@link #settlementWindowFor(Shop, LocalDate)}。 */
    @Deprecated
    public static Date[] windowFor(Shop shop, LocalDate businessDay) {
        return operationalWindowFor(shop, businessDay);
    }

    /** @deprecated 推荐使用 {@link #operationalBusinessDay(Shop, LocalDateTime)}。 */
    @Deprecated
    public static LocalDate businessDayFor(Shop shop, LocalDate today) {
        return operationalBusinessDay(shop, LocalDateTime.of(today, LocalTime.now()));
    }

    /** @deprecated 推荐使用 {@link #operationalSettlementDay(Shop, LocalDateTime)}。 */
    @Deprecated
    public static LocalDate operationalSettlementDay(Shop shop, LocalDateTime now) {
        return operationalBusinessDay(shop, now);
    }

    @Deprecated
    public static LocalDate operationalSettlementDay(Shop shop) {
        return operationalBusinessDay(shop);
    }

    /**
     * 结算起始时刻（24小时周期起始点即为 settle_time）。
     */
    public static LocalTime settlementStartTime(Shop shop) {
        return requireSettleTime(shop);
    }

    /**
     * 判断指定时刻当前门店是否正处于营业时段（Business Hours）。
     *
     * <p>营业时段判定规则：
     * 1. 优先按时钟窗口判定：
     *    - 从开门营业时间 {@code open_time} 到打烊结束时间 {@code close_time}；
     *    - 跨天场景（如 16:00 ~ 次日 02:00，即 open > close）：当前时刻 >= open 或 < close 均属于营业时段；
     *    - 非跨天场景（如 10:00 ~ 22:00，即 open < close）：当前时刻 >= open 且 < close 属于营业时段；
     *    - 若 open == close 且非空：视为 24 小时全天营业；
     *    - 单边配置容错：仅配 close_time 回退 16:00 起点；仅配 open_time 回退 settle_time 或 04:00 打烊；
     *    - 若 open_time 和 close_time 均未配置：不启用时钟窗口校验（返回 false）；
     * 2. 时区基准：统一基于中国标准时间（Asia/Shanghai）。
     *
     * @param shop 门店对象
     * @param now  待判定的时刻
     * @return true 若处于营业时段，false 若处于打烊/休息时段
     */
    public static boolean isWithinBusinessHours(Shop shop, LocalDateTime now) {
        if (shop == null || now == null) {
            return false;
        }
        String openTimeStr = shop.getOpen_time();
        String closeTimeStr = shop.getClose_time();

        if ((openTimeStr == null || openTimeStr.trim().isEmpty())
                && (closeTimeStr == null || closeTimeStr.trim().isEmpty())) {
            return false;
        }

        LocalTime open = parse(openTimeStr);
        LocalTime close = parse(closeTimeStr);

        if (open == null && close != null) {
            open = LocalTime.of(16, 0);
        } else if (open != null && close == null) {
            close = resolveSettleTimeOrDefault(shop);
        }

        if (open == null || close == null) {
            return false;
        }

        LocalTime current = now.toLocalTime();
        if (open.isBefore(close)) {
            return !current.isBefore(open) && current.isBefore(close);
        } else if (open.isAfter(close)) {
            return !current.isBefore(open) || current.isBefore(close);
        } else {
            return true;
        }
    }

    public static boolean isWithinBusinessHours(Shop shop) {
        return isWithinBusinessHours(shop, LocalDateTime.now(ZONE));
    }

    private static String toText(Date date) {
        return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(date);
    }

    private static LocalTime parse(String text) {
        if (text == null) return null;
        String t = text.trim();
        if (t.length() > 5) t = t.substring(0, 5);
        try {
            return LocalTime.parse(t);
        } catch (Exception e) {
            return null;
        }
    }
}
