package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.WeChatPrepayNineFoldSettings;
import com.lanf.entity.Order;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.entity.PaymentNinefoldEntity;
import com.lanf.payment.mapper.PaymentNinefoldMapper;
import com.lanf.payment.support.PaymentAdminShopScope;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 门店夜间九折（按 {@code shop_id} 隔离，{@code shop_id=0} 为全店默认；各店独立 {@code enabled} 开关）。
 */
@Service
public class PaymentNinefoldService {

    private static final double DEFAULT_PAY_RATE = 0.9d;
    private static final double DEFAULT_MIN_BASE_YUAN = 60d;
    private static final LocalTime DEFAULT_TIME_START = LocalTime.of(0, 30);
    private static final LocalTime DEFAULT_TIME_END = LocalTime.of(3, 0);
    private static final ZoneId DEFAULT_ZONE = ZoneId.of("Asia/Shanghai");
    private static final List<String> SUPPORTED_CANONICAL = Collections.unmodifiableList(
            java.util.Arrays.asList("堂食", "打包", "外卖"));

    @Autowired
    private PaymentNinefoldMapper ninefoldMapper;
    @Autowired
    private PaymentConfigCache configCache;

    public PaymentNinefoldEntity loadRowFromDb(int shopId) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        return ninefoldMapper.selectOne(new QueryWrapper<PaymentNinefoldEntity>()
                .eq("shop_id", sid)
                .last("LIMIT 1"));
    }

    public ResolvedNinefold resolve(Integer shopId) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentNinefoldEntity shopRow = configCache.getNinefoldRow(sid);
        PaymentNinefoldEntity globalRow = sid == PaymentConfigCache.GLOBAL_SHOP_ID
                ? null
                : configCache.getNinefoldRow(PaymentConfigCache.GLOBAL_SHOP_ID);
        if (shopRow == null && sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            shopRow = loadRowFromDb(sid);
            if (shopRow != null) {
                configCache.putNinefold(sid, shopRow);
            }
        }
        if (globalRow == null && sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            globalRow = configCache.getNinefoldRow(PaymentConfigCache.GLOBAL_SHOP_ID);
            if (globalRow == null) {
                globalRow = loadRowFromDb(PaymentConfigCache.GLOBAL_SHOP_ID);
                if (globalRow != null) {
                    configCache.putNinefold(PaymentConfigCache.GLOBAL_SHOP_ID, globalRow);
                }
            }
        }
        if (shopRow == null && sid == PaymentConfigCache.GLOBAL_SHOP_ID) {
            shopRow = loadRowFromDb(PaymentConfigCache.GLOBAL_SHOP_ID);
            if (shopRow != null) {
                configCache.putNinefold(PaymentConfigCache.GLOBAL_SHOP_ID, shopRow);
            }
            globalRow = shopRow;
        }
        ResolvedNinefold r = new ResolvedNinefold();
        r.shopId = sid;
        r.enabled = resolveBool(shopRow, globalRow, false);
        r.payRate = resolvePayRate(shopRow, globalRow);
        r.minBaseYuan = resolveMinBase(shopRow, globalRow);
        r.windowStart = resolveTimeStart(shopRow, globalRow);
        r.windowEnd = resolveTimeEnd(shopRow, globalRow);
        r.zone = resolveZone(shopRow, globalRow);
        r.eligibleDiningTypes = resolveEligibleTypes(shopRow, globalRow);
        r.hasOwnConfig = shopRow != null && sid != PaymentConfigCache.GLOBAL_SHOP_ID;
        r.inheritsGlobal = sid != PaymentConfigCache.GLOBAL_SHOP_ID && shopRow == null;
        return r;
    }

    public Map<String, Object> toPublicMap(Integer shopId) {
        return resolve(shopId).toPublicMap();
    }

    public Map<String, Object> toAdminMap(int shopId) {
        ResolvedNinefold r = resolve(shopId);
        Map<String, Object> out = new LinkedHashMap<>(r.toPublicMap());
        out.put("targetShopId", r.shopId);
        out.put("scope", PaymentAdminShopScope.scopeLabel(r.shopId));
        out.put("hasOwnConfig", r.hasOwnConfig);
        out.put("inheritsGlobal", r.inheritsGlobal);
        return out;
    }

    public boolean qualifiesForNineFold(Integer shopId, boolean usesCoupon, Date orderTime,
                                        double basePaidYuanAfterCoupon, String dineInOrTakeOut) {
        return resolve(shopId).qualifiesForNineFold(usesCoupon, orderTime, basePaidYuanAfterCoupon, dineInOrTakeOut);
    }

    public static int resolveOrderShopId(Order order) {
        if (order == null) {
            return 1;
        }
        Integer oid = order.getShop_id();
        return oid != null && oid > 0 ? oid : 1;
    }

    public PaymentNinefoldEntity upsert(int shopId, Map<String, Object> body) {
        if (body == null) {
            throw new IllegalArgumentException("请求体不能为空");
        }
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentNinefoldEntity row = loadRowFromDb(sid);
        ResolvedNinefold current = resolve(sid);
        if (row == null) {
            row = new PaymentNinefoldEntity();
            row.setShop_id(sid);
            row.setEnabled(boolToInt(current.enabled));
            row.setPay_rate(BigDecimal.valueOf(current.payRate));
            row.setMin_base_yuan(BigDecimal.valueOf(current.minBaseYuan));
            row.setTime_start(current.windowStart.toString());
            row.setTime_end(current.windowEnd.toString());
            row.setZone_id(current.zone.getId());
            row.setEligible_dining_types(WeChatPrepayNineFoldSettings.serializeEligibleDiningTypes(
                    current.eligibleDiningTypes));
        }
        if (body.containsKey("enabled")) {
            row.setEnabled(boolToInt(parseBool(body.get("enabled"), intToBool(row.getEnabled()))));
        }
        if (body.containsKey("payRate")) {
            Double d = parseDouble(body.get("payRate"));
            if (d != null) {
                row.setPay_rate(BigDecimal.valueOf(clampPayRate(d)));
            }
        }
        if (body.containsKey("minBaseYuan")) {
            Double d = parseDouble(body.get("minBaseYuan"));
            if (d != null) {
                row.setMin_base_yuan(BigDecimal.valueOf(d >= 0 ? d : 0d));
            }
        }
        if (body.containsKey("timeStart")) {
            LocalTime t = parseLocalTime(body.get("timeStart"));
            if (t == null) {
                throw new IllegalArgumentException("timeStart 格式须为 HH:mm 或 HH:mm:ss");
            }
            row.setTime_start(t.toString());
        }
        if (body.containsKey("timeEnd")) {
            LocalTime t = parseLocalTime(body.get("timeEnd"));
            if (t == null) {
                throw new IllegalArgumentException("timeEnd 格式须为 HH:mm 或 HH:mm:ss");
            }
            row.setTime_end(t.toString());
        }
        if (body.containsKey("zoneId")) {
            Object z = body.get("zoneId");
            if (z != null && StringUtils.hasText(z.toString())) {
                try {
                    row.setZone_id(ZoneId.of(z.toString().trim()).getId());
                } catch (Exception e) {
                    throw new IllegalArgumentException("zoneId 非法：" + z);
                }
            }
        }
        if (body.containsKey("eligibleDiningTypes")) {
            List<String> types = parseEligibleBody(body.get("eligibleDiningTypes"));
            if (types == null || types.isEmpty()) {
                throw new IllegalArgumentException("eligibleDiningTypes 至少包含一项：堂食、打包、外卖");
            }
            LinkedHashSet<String> normalized = new LinkedHashSet<>();
            for (String raw : types) {
                if (raw == null || raw.trim().isEmpty()) {
                    continue;
                }
                String canonical = WeChatPrepayNineFoldSettings.canonicalDiningType(raw.trim());
                if (!WeChatPrepayNineFoldSettings.isSupportedDiningTypeLabel(canonical)) {
                    throw new IllegalArgumentException("不支持的就餐方式：" + raw);
                }
                normalized.add(canonical);
            }
            if (normalized.isEmpty()) {
                throw new IllegalArgumentException("eligibleDiningTypes 至少包含一项：堂食、打包、外卖");
            }
            row.setEligible_dining_types(
                    WeChatPrepayNineFoldSettings.serializeEligibleDiningTypes(normalized));
        }
        if (row.getId() == null) {
            ninefoldMapper.insert(row);
        } else {
            ninefoldMapper.updateById(row);
        }
        configCache.putNinefold(sid, row);
        return row;
    }

    public static final class ResolvedNinefold {
        public int shopId;
        public boolean enabled;
        public double payRate;
        public double minBaseYuan;
        public LocalTime windowStart;
        public LocalTime windowEnd;
        public ZoneId zone;
        public List<String> eligibleDiningTypes;
        public boolean hasOwnConfig;
        public boolean inheritsGlobal;

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

        public boolean isTimeWindowActive(Date date) {
            Instant instant = date == null ? Instant.now() : date.toInstant();
            LocalTime t = instant.atZone(zone).toLocalTime();
            return isLocalTimeInWindow(t, windowStart, windowEnd);
        }

        public boolean isEligibleDiningType(String dineInOrTakeOut) {
            String canonical = WeChatPrepayNineFoldSettings.canonicalDiningType(dineInOrTakeOut);
            return !canonical.isEmpty() && eligibleDiningTypes.contains(canonical);
        }

        public Map<String, Object> toPublicMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("shopId", shopId);
            m.put("enabled", enabled);
            m.put("payRate", payRate);
            m.put("minBaseYuan", minBaseYuan);
            m.put("timeStart", windowStart.toString());
            m.put("timeEnd", windowEnd.toString());
            m.put("zoneId", zone.getId());
            List<String> types = new ArrayList<>(eligibleDiningTypes);
            m.put("eligibleDiningTypes", types);
            m.put("dineInOnly", types.size() == 1 && "堂食".equals(types.get(0)));
            m.put("supportedDiningTypes", SUPPORTED_CANONICAL);
            return m;
        }
    }

    private static boolean resolveBool(PaymentNinefoldEntity shop, PaymentNinefoldEntity global, boolean def) {
        if (shop != null && shop.getEnabled() != null) {
            return intToBool(shop.getEnabled());
        }
        if (global != null && global.getEnabled() != null) {
            return intToBool(global.getEnabled());
        }
        return def;
    }

    private static double resolvePayRate(PaymentNinefoldEntity shop, PaymentNinefoldEntity global) {
        if (shop != null && shop.getPay_rate() != null) {
            return clampPayRate(shop.getPay_rate().doubleValue());
        }
        if (global != null && global.getPay_rate() != null) {
            return clampPayRate(global.getPay_rate().doubleValue());
        }
        return DEFAULT_PAY_RATE;
    }

    private static double resolveMinBase(PaymentNinefoldEntity shop, PaymentNinefoldEntity global) {
        if (shop != null && shop.getMin_base_yuan() != null) {
            return shop.getMin_base_yuan().doubleValue();
        }
        if (global != null && global.getMin_base_yuan() != null) {
            return global.getMin_base_yuan().doubleValue();
        }
        return DEFAULT_MIN_BASE_YUAN;
    }

    private static LocalTime resolveTimeStart(PaymentNinefoldEntity shop, PaymentNinefoldEntity global) {
        if (shop != null && StringUtils.hasText(shop.getTime_start())) {
            return parseLocalTimeOrDefault(shop.getTime_start(), DEFAULT_TIME_START);
        }
        if (global != null && StringUtils.hasText(global.getTime_start())) {
            return parseLocalTimeOrDefault(global.getTime_start(), DEFAULT_TIME_START);
        }
        return DEFAULT_TIME_START;
    }

    private static LocalTime resolveTimeEnd(PaymentNinefoldEntity shop, PaymentNinefoldEntity global) {
        if (shop != null && StringUtils.hasText(shop.getTime_end())) {
            return parseLocalTimeOrDefault(shop.getTime_end(), DEFAULT_TIME_END);
        }
        if (global != null && StringUtils.hasText(global.getTime_end())) {
            return parseLocalTimeOrDefault(global.getTime_end(), DEFAULT_TIME_END);
        }
        return DEFAULT_TIME_END;
    }

    private static ZoneId resolveZone(PaymentNinefoldEntity shop, PaymentNinefoldEntity global) {
        if (shop != null && StringUtils.hasText(shop.getZone_id())) {
            return parseZoneOrDefault(shop.getZone_id(), DEFAULT_ZONE);
        }
        if (global != null && StringUtils.hasText(global.getZone_id())) {
            return parseZoneOrDefault(global.getZone_id(), DEFAULT_ZONE);
        }
        return DEFAULT_ZONE;
    }

    private static List<String> resolveEligibleTypes(PaymentNinefoldEntity shop, PaymentNinefoldEntity global) {
        if (shop != null && StringUtils.hasText(shop.getEligible_dining_types())) {
            return WeChatPrepayNineFoldSettings.parseEligibleDiningTypesRaw(shop.getEligible_dining_types());
        }
        if (global != null && StringUtils.hasText(global.getEligible_dining_types())) {
            return WeChatPrepayNineFoldSettings.parseEligibleDiningTypesRaw(global.getEligible_dining_types());
        }
        return Collections.singletonList("堂食");
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

    private static LocalTime parseLocalTimeOrDefault(String v, LocalTime def) {
        try {
            return LocalTime.parse(v.trim());
        } catch (Exception e) {
            return def;
        }
    }

    private static ZoneId parseZoneOrDefault(String v, ZoneId def) {
        try {
            return ZoneId.of(v.trim());
        } catch (Exception e) {
            return def;
        }
    }

    private static double clampPayRate(double r) {
        if (r <= 0 || r > 1d || Double.isNaN(r)) {
            return DEFAULT_PAY_RATE;
        }
        if (r < 0.5d) {
            return 0.5d;
        }
        return r;
    }

    private static int boolToInt(boolean v) {
        return v ? 1 : 0;
    }

    private static boolean intToBool(Integer v) {
        return v != null && v != 0;
    }

    private static boolean parseBool(Object raw, boolean def) {
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        if (raw instanceof Number) {
            return ((Number) raw).intValue() != 0;
        }
        if (raw != null && StringUtils.hasText(raw.toString())) {
            String s = raw.toString().trim();
            if ("1".equals(s) || "true".equalsIgnoreCase(s)) {
                return true;
            }
            if ("0".equals(s) || "false".equalsIgnoreCase(s)) {
                return false;
            }
        }
        return def;
    }

    private static Double parseDouble(Object raw) {
        if (raw instanceof Number) {
            return ((Number) raw).doubleValue();
        }
        if (raw != null && StringUtils.hasText(raw.toString())) {
            try {
                return Double.parseDouble(raw.toString().trim());
            } catch (NumberFormatException ignore) {
            }
        }
        return null;
    }

    private static LocalTime parseLocalTime(Object raw) {
        if (raw == null || !StringUtils.hasText(raw.toString())) {
            return null;
        }
        try {
            return LocalTime.parse(raw.toString().trim());
        } catch (Exception e) {
            return null;
        }
    }

    @SuppressWarnings("unchecked")
    private static List<String> parseEligibleBody(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof List) {
            List<String> out = new ArrayList<>();
            for (Object o : (List<?>) raw) {
                if (o != null && StringUtils.hasText(o.toString())) {
                    out.add(o.toString().trim());
                }
            }
            return out;
        }
        return WeChatPrepayNineFoldSettings.parseEligibleDiningTypesRaw(raw.toString());
    }
}
