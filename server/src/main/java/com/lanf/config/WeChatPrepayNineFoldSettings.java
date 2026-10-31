package com.lanf.config;

import com.lanf.constant.WeChatPrepayNineFoldConfigKeys;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 统一下单夜间九折规则（可运行时修改，持久化见 {@link SystemConfigSync} 与 {@code t_system_config}）。
 */
@Component
public class WeChatPrepayNineFoldSettings {

    private static final List<String> SUPPORTED_CANONICAL = Arrays.asList("堂食", "打包", "外卖");

    private volatile boolean enabled = true;
    private volatile double payRate = 0.9;
    private volatile double minBaseYuan = 60d;
    private volatile ZoneId zone = ZoneId.of("Asia/Shanghai");
    private volatile LocalTime windowStart = LocalTime.of(0, 30);
    private volatile LocalTime windowEnd = LocalTime.of(3, 0);
    private volatile Set<String> eligibleDiningTypes = defaultEligibleDiningTypes();

    public boolean isEnabled() {
        return enabled;
    }

    public double getPayRate() {
        return payRate;
    }

    public double getMinBaseYuan() {
        return minBaseYuan;
    }

    public ZoneId getZone() {
        return zone;
    }

    public LocalTime getWindowStart() {
        return windowStart;
    }

    public LocalTime getWindowEnd() {
        return windowEnd;
    }

    public List<String> getEligibleDiningTypes() {
        return new ArrayList<>(eligibleDiningTypes);
    }

    /**
     * 是否满足夜间九折全部条件：开关、未用券、时段、最低金额、就餐方式。
     */
    public boolean qualifiesForNineFold(boolean usesCoupon, Date orderTime, double basePaidYuanAfterCoupon,
                                        String dineInOrTakeOut) {
        if (!enabled || usesCoupon) {
            return false;
        }
        if (!isTimeWindowActive(orderTime)) {
            return false;
        }
        if (basePaidYuanAfterCoupon < minBaseYuan) {
            return false;
        }
        return isEligibleDiningType(dineInOrTakeOut);
    }

    /**
     * 当前是否在配置的生效时段内（按 {@link #getZone()} 的「现在」的本地时间）。
     */
    public boolean isTimeWindowActiveNow() {
        return isTimeWindowActive(Instant.now());
    }

    /**
     * 指定时刻是否在九折时间窗内（按 {@link #getZone()} 的本地时间判断）。
     * 用于以订单下单时间为准的九折，而非付款时刻。
     */
    public boolean isTimeWindowActive(Instant instant) {
        if (instant == null) {
            return false;
        }
        LocalTime t = instant.atZone(zone).toLocalTime();
        return isLocalTimeInWindow(t, windowStart, windowEnd);
    }

    public boolean isTimeWindowActive(Date date) {
        if (date == null) {
            return isTimeWindowActive(Instant.now());
        }
        return isTimeWindowActive(date.toInstant());
    }

    private static boolean isLocalTimeInWindow(LocalTime t, LocalTime start, LocalTime end) {
        if (t == null || start == null || end == null) {
            return false;
        }
        if (end.isBefore(start)) {
            return !t.isBefore(start) || !t.isAfter(end);
        }
        return !t.isBefore(start) && !t.isAfter(end);
    }

    /** 订单就餐方式是否在配置的适用列表内。 */
    public boolean isEligibleDiningType(String dineInOrTakeOut) {
        String canonical = canonicalDiningType(dineInOrTakeOut);
        return !canonical.isEmpty() && eligibleDiningTypes.contains(canonical);
    }

    /**
     * 将订单/配置中的就餐方式归一化为：堂食、打包、外卖。
     */
    public static String canonicalDiningType(String raw) {
        if (raw == null) {
            return "";
        }
        String t = raw.trim();
        if (t.isEmpty()) {
            return "";
        }
        if ("堂食".equals(t) || "dine_in".equalsIgnoreCase(t) || "dinein".equalsIgnoreCase(t)) {
            return "堂食";
        }
        if ("打包".equals(t) || "take_out".equalsIgnoreCase(t) || "takeout".equalsIgnoreCase(t)) {
            return "打包";
        }
        if ("外卖".equals(t) || "delivery".equalsIgnoreCase(t) || "waimai".equalsIgnoreCase(t)) {
            return "外卖";
        }
        return t;
    }

    public static boolean isSupportedDiningTypeLabel(String raw) {
        String c = canonicalDiningType(raw);
        return SUPPORTED_CANONICAL.contains(c);
    }

    /**
     * C 端展示用（不含敏感业务密钥）。
     */
    public Map<String, Object> toPublicMap() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("enabled", enabled);
        m.put("payRate", payRate);
        m.put("minBaseYuan", minBaseYuan);
        m.put("timeStart", windowStart.toString());
        m.put("timeEnd", windowEnd.toString());
        m.put("zoneId", zone.getId());
        List<String> types = getEligibleDiningTypes();
        m.put("eligibleDiningTypes", types);
        m.put("dineInOnly", types.size() == 1 && "堂食".equals(types.get(0)));
        m.put("supportedDiningTypes", SUPPORTED_CANONICAL);
        return m;
    }

    /**
     * 启动时从库表逐条加载。
     */
    public void applyFromKeyValue(String key, String rawValue) {
        if (key == null) {
            return;
        }
        String k = key.trim();
        String v = rawValue == null ? "" : rawValue.trim();
        if (WeChatPrepayNineFoldConfigKeys.ENABLED.equals(k)) {
            enabled = parseBool(v, enabled);
        } else if (WeChatPrepayNineFoldConfigKeys.PAY_RATE.equals(k)) {
            payRate = parsePayRate(v, payRate);
        } else if (WeChatPrepayNineFoldConfigKeys.MIN_BASE_YUAN.equals(k)) {
            minBaseYuan = parseMinBase(v, minBaseYuan);
        } else if (WeChatPrepayNineFoldConfigKeys.TIME_START.equals(k)) {
            windowStart = parseLocalTime(v, windowStart);
        } else if (WeChatPrepayNineFoldConfigKeys.TIME_END.equals(k)) {
            windowEnd = parseLocalTime(v, windowEnd);
        } else if (WeChatPrepayNineFoldConfigKeys.ZONE_ID.equals(k)) {
            zone = parseZone(v, zone);
        } else if (WeChatPrepayNineFoldConfigKeys.ELIGIBLE_DINING_TYPES.equals(k)) {
            setEligibleDiningTypes(parseEligibleDiningTypesRaw(v));
        }
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public void setPayRate(double payRate) {
        this.payRate = clampPayRate(payRate);
    }

    public void setMinBaseYuan(double minBaseYuan) {
        this.minBaseYuan = minBaseYuan >= 0 ? minBaseYuan : 0d;
    }

    public void setWindowStart(LocalTime windowStart) {
        if (windowStart != null) {
            this.windowStart = windowStart;
        }
    }

    public void setWindowEnd(LocalTime windowEnd) {
        if (windowEnd != null) {
            this.windowEnd = windowEnd;
        }
    }

    public void setZone(ZoneId zone) {
        if (zone != null) {
            this.zone = zone;
        }
    }

    /**
     * @param types 就餐方式列表（堂食/打包/外卖或英文别名）；空或无效时保持默认仅堂食
     */
    public void setEligibleDiningTypes(List<String> types) {
        LinkedHashSet<String> normalized = normalizeEligibleTypes(types);
        if (normalized.isEmpty()) {
            this.eligibleDiningTypes = defaultEligibleDiningTypes();
            return;
        }
        this.eligibleDiningTypes = Collections.unmodifiableSet(normalized);
    }

    public static String serializeEligibleDiningTypes(Collection<String> types) {
        LinkedHashSet<String> normalized = normalizeEligibleTypes(types);
        if (normalized.isEmpty()) {
            normalized = new LinkedHashSet<>(defaultEligibleDiningTypes());
        }
        StringBuilder sb = new StringBuilder("[");
        boolean first = true;
        for (String t : normalized) {
            if (!first) {
                sb.append(',');
            }
            sb.append('"').append(t.replace("\"", "")).append('"');
            first = false;
        }
        sb.append(']');
        return sb.toString();
    }

    private static Set<String> defaultEligibleDiningTypes() {
        return Collections.unmodifiableSet(new LinkedHashSet<>(Collections.singletonList("堂食")));
    }

    private static LinkedHashSet<String> normalizeEligibleTypes(Collection<String> types) {
        LinkedHashSet<String> normalized = new LinkedHashSet<>();
        if (types == null) {
            return normalized;
        }
        for (String raw : types) {
            if (raw == null || raw.trim().isEmpty()) {
                continue;
            }
            String canonical = canonicalDiningType(raw.trim());
            if (SUPPORTED_CANONICAL.contains(canonical)) {
                normalized.add(canonical);
            }
        }
        return normalized;
    }

    public static List<String> parseEligibleDiningTypesRaw(String raw) {
        if (raw == null || raw.trim().isEmpty()) {
            return Collections.singletonList("堂食");
        }
        String s = raw.trim();
        List<String> parts;
        if (s.startsWith("[")) {
            parts = parseJsonStringArray(s);
        } else {
            parts = new ArrayList<>();
            for (String p : s.split(",")) {
                if (!p.trim().isEmpty()) {
                    parts.add(p.trim());
                }
            }
        }
        LinkedHashSet<String> normalized = normalizeEligibleTypes(parts);
        if (normalized.isEmpty()) {
            return Collections.singletonList("堂食");
        }
        return new ArrayList<>(normalized);
    }

    private static List<String> parseJsonStringArray(String json) {
        List<String> out = new ArrayList<>();
        if (json == null || json.length() < 2) {
            return out;
        }
        String inner = json.trim();
        if (inner.startsWith("[") && inner.endsWith("]")) {
            inner = inner.substring(1, inner.length() - 1).trim();
        }
        if (inner.isEmpty()) {
            return out;
        }
        for (String part : inner.split(",")) {
            String t = part.trim();
            if ((t.startsWith("\"") && t.endsWith("\"") && t.length() >= 2)
                    || (t.startsWith("'") && t.endsWith("'") && t.length() >= 2)) {
                t = t.substring(1, t.length() - 1).trim();
            }
            if (!t.isEmpty()) {
                out.add(t);
            }
        }
        return out;
    }

    private static boolean parseBool(String v, boolean def) {
        if (v.isEmpty()) {
            return def;
        }
        if ("1".equals(v) || "true".equalsIgnoreCase(v) || "yes".equalsIgnoreCase(v)) {
            return true;
        }
        if ("0".equals(v) || "false".equalsIgnoreCase(v) || "no".equalsIgnoreCase(v)) {
            return false;
        }
        return def;
    }

    private static double parsePayRate(String v, double def) {
        if (v.isEmpty()) {
            return def;
        }
        try {
            return clampPayRate(Double.parseDouble(v));
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static double clampPayRate(double r) {
        if (r <= 0 || r > 1d || Double.isNaN(r)) {
            return 0.9;
        }
        if (r < 0.5d) {
            return 0.5d;
        }
        return r;
    }

    private static double parseMinBase(String v, double def) {
        if (v.isEmpty()) {
            return def;
        }
        try {
            double x = Double.parseDouble(v);
            return x >= 0 ? x : def;
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static LocalTime parseLocalTime(String v, LocalTime def) {
        if (v.isEmpty()) {
            return def;
        }
        try {
            return LocalTime.parse(v);
        } catch (Exception e) {
            return def;
        }
    }

    private static ZoneId parseZone(String v, ZoneId def) {
        if (v.isEmpty()) {
            return def;
        }
        try {
            return ZoneId.of(v);
        } catch (Exception e) {
            return def;
        }
    }
}
