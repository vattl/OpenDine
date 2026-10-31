package com.lanf.util;

import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.util.TakeoutDeliveryFeeCalculator;

import java.math.BigDecimal;
import java.util.Date;
import java.util.Map;

/**
 * 运营端保存外卖配置：兼容 camelCase / snake_case，以及 boolean 开关写 0/1。
 */
public final class ShopTakeoutConfigFormHelper {

    private ShopTakeoutConfigFormHelper() {
    }

    public static ShopTakeoutConfig newDefault(int shopId) {
        ShopTakeoutConfig d = new ShopTakeoutConfig();
        d.setShop_id(shopId);
        d.setEnabled(0);
        d.setDelivery_fee(BigDecimal.ZERO);
        d.setMin_order_amount(new BigDecimal("68.00"));
        d.setFree_delivery_threshold(new BigDecimal("168.00"));
        d.setMax_delivery_distance_km(new BigDecimal("5.00"));
        d.setFree_delivery_max_distance_km(new BigDecimal("5.00"));
        d.setDelivery_fee_tiers_json(TakeoutDeliveryFeeCalculator.DEFAULT_TIERS_JSON);
        d.setLead_time_minutes(30);
        d.setRemark("起送68元；1-3km 5元、3-4km 8元、4-5km 10元；满168元5公里内免配送费");
        return d;
    }

    public static void applyMap(ShopTakeoutConfig target, Map<String, Object> body) {
        if (target == null || body == null || body.isEmpty()) {
            return;
        }
        if (hasAny(body, "enabled")) {
            target.setEnabled(readToggleFromMap(body, target.getEnabled() != null ? target.getEnabled() : 0, "enabled"));
        }
        if (hasAny(body, "delivery_fee", "deliveryFee")) {
            target.setDelivery_fee(parseDecimal(body, "delivery_fee", "deliveryFee", target.getDelivery_fee()));
        }
        if (hasAny(body, "min_order_amount", "minOrderAmount")) {
            target.setMin_order_amount(parseDecimal(body, "min_order_amount", "minOrderAmount", target.getMin_order_amount()));
        }
        if (hasAny(body, "free_delivery_threshold", "freeDeliveryThreshold")) {
            target.setFree_delivery_threshold(parseDecimal(body, "free_delivery_threshold", "freeDeliveryThreshold",
                    target.getFree_delivery_threshold()));
        }
        if (hasAny(body, "max_delivery_distance_km", "maxDeliveryDistanceKm")) {
            target.setMax_delivery_distance_km(parseDecimal(body, "max_delivery_distance_km", "maxDeliveryDistanceKm",
                    target.getMax_delivery_distance_km()));
        }
        if (hasAny(body, "free_delivery_max_distance_km", "freeDeliveryMaxDistanceKm")) {
            target.setFree_delivery_max_distance_km(parseDecimal(body, "free_delivery_max_distance_km",
                    "freeDeliveryMaxDistanceKm", target.getFree_delivery_max_distance_km()));
        }
        if (hasAny(body, "delivery_fee_tiers_json", "deliveryFeeTiersJson")) {
            target.setDelivery_fee_tiers_json(parseString(body, "delivery_fee_tiers_json", "deliveryFeeTiersJson"));
        }
        if (hasAny(body, "lead_time_minutes", "leadTimeMinutes")) {
            target.setLead_time_minutes(parseInteger(body, "lead_time_minutes", "leadTimeMinutes",
                    target.getLead_time_minutes()));
        }
        if (hasAny(body, "remark")) {
            target.setRemark(parseString(body, "remark"));
        }
        if (hasAny(body, "zsq_from_address_id", "zsqFromAddressId")) {
            target.setZsq_from_address_id(parseLong(body, "zsq_from_address_id", "zsqFromAddressId"));
        }
        if (hasAny(body, "zsq_city_name", "zsqCityName")) {
            target.setZsq_city_name(parseString(body, "zsq_city_name", "zsqCityName"));
        }
        target.setUpdated_at(new Date());
    }

    public static Integer parseToggle(Object value, int defaultVal) {
        Integer n = parseToggleOrNull(value);
        return n != null ? n : defaultVal;
    }

    public static Integer parseToggleOrNull(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean) {
            return (Boolean) value ? 1 : 0;
        }
        if (value instanceof Number) {
            return ((Number) value).intValue() != 0 ? 1 : 0;
        }
        String s = String.valueOf(value).trim();
        if (s.isEmpty()) {
            return null;
        }
        if ("1".equals(s) || "true".equalsIgnoreCase(s) || "yes".equalsIgnoreCase(s)) {
            return 1;
        }
        if ("0".equals(s) || "false".equalsIgnoreCase(s) || "no".equalsIgnoreCase(s)) {
            return 0;
        }
        return null;
    }

    private static int readToggleFromMap(Map<String, Object> body, int defaultVal, String... keys) {
        return parseToggle(first(body, keys), defaultVal);
    }

    private static boolean hasAny(Map<String, Object> body, String... keys) {
        for (String k : keys) {
            if (body.containsKey(k)) {
                return true;
            }
        }
        return false;
    }

    private static Object first(Map<String, Object> body, String... keys) {
        for (String k : keys) {
            if (body.containsKey(k)) {
                return body.get(k);
            }
        }
        return null;
    }

    private static String parseString(Map<String, Object> body, String... keys) {
        Object v = first(body, keys);
        return v == null ? null : String.valueOf(v);
    }

    private static Integer parseInteger(Map<String, Object> body, String k1, String k2, Integer def) {
        Object v = first(body, k1, k2);
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        if (v != null) {
            try {
                return Integer.parseInt(String.valueOf(v).trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return def;
    }

    private static Long parseLong(Map<String, Object> body, String k1, String k2) {
        Object v = first(body, k1, k2);
        if (v == null || String.valueOf(v).trim().isEmpty()) {
            return null;
        }
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        try {
            return Long.parseLong(String.valueOf(v).trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static BigDecimal parseDecimal(Map<String, Object> body, String k1, String k2, BigDecimal def) {
        Object v = first(body, k1, k2);
        if (v == null || String.valueOf(v).trim().isEmpty()) {
            return def;
        }
        if (v instanceof BigDecimal) {
            return (BigDecimal) v;
        }
        if (v instanceof Number) {
            return BigDecimal.valueOf(((Number) v).doubleValue());
        }
        try {
            return new BigDecimal(String.valueOf(v).trim());
        } catch (NumberFormatException e) {
            return def;
        }
    }
}
