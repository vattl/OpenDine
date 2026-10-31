package com.lanf.util;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Shop;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.entity.UserAddress;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * 外卖配送费：按门店与收货点距离（公里，优先路网）匹配阶梯；满额且在免配距离内则 0 元。
 */
public final class TakeoutDeliveryFeeCalculator {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final TypeReference<List<DistanceFeeTier>> TIER_LIST = new TypeReference<List<DistanceFeeTier>>() {};

    /** 未配置 tiers_json 时的默认阶梯（市区规则） */
    public static final String DEFAULT_TIERS_JSON =
            "[{\"toKm\":3,\"fee\":5},{\"toKm\":4,\"fee\":8},{\"toKm\":5,\"fee\":10}]";

    private TakeoutDeliveryFeeCalculator() {
    }

    public static class DistanceFeeTier {
        public Double toKm;
        public Double fee;
    }

    public static class Quote {
        public final BigDecimal deliveryFee;
        public final double distanceKm;
        public final boolean deliverable;
        public final boolean freeDelivery;
        public final String message;
        /** {@code route} 路网距离；{@code straight_line} 直线距离；未算距时为 null */
        public final String distanceMethod;

        public Quote(BigDecimal deliveryFee, double distanceKm, boolean deliverable, boolean freeDelivery,
                     String message, String distanceMethod) {
            this.deliveryFee = deliveryFee;
            this.distanceKm = distanceKm;
            this.deliverable = deliverable;
            this.freeDelivery = freeDelivery;
            this.message = message;
            this.distanceMethod = distanceMethod;
        }
    }

    public static Quote quote(ShopTakeoutConfig cfg, Shop shop, UserAddress address, double goodsSubtotalYuan) {
        Double km = resolveDistanceKm(shop, address);
        String method = km != null ? METHOD_STRAIGHT_LINE : null;
        return quoteWithDistance(cfg, goodsSubtotalYuan, km, method);
    }

    public static Quote quote(ShopTakeoutConfig cfg, Shop shop, UserAddress address, double goodsSubtotalYuan,
                              TakeoutDistanceResolver distanceResolver) {
        if (distanceResolver != null) {
            TakeoutDistanceResolver.Result dr = distanceResolver.resolve(shop, address);
            return quoteWithDistance(cfg, goodsSubtotalYuan, dr.distanceKm, dr.distanceMethod);
        }
        return quote(cfg, shop, address, goodsSubtotalYuan);
    }

    private static final String METHOD_STRAIGHT_LINE = TakeoutDistanceResolver.METHOD_STRAIGHT_LINE;

    static Quote quoteWithDistance(ShopTakeoutConfig cfg, double goodsSubtotalYuan, Double distanceKm,
                                   String distanceMethod) {
        if (cfg == null || cfg.getEnabled() == null || cfg.getEnabled() != 1) {
            return new Quote(BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP), 0d, false, false,
                    "门店未开启外卖", distanceMethod);
        }
        BigDecimal min = cfg.getMin_order_amount() != null ? cfg.getMin_order_amount() : BigDecimal.ZERO;
        if (BigDecimal.valueOf(goodsSubtotalYuan).compareTo(min) < 0) {
            return new Quote(BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP), 0d, true, false,
                    "未达起送价（满 " + min.stripTrailingZeros().toPlainString() + " 元）", distanceMethod);
        }

        if (distanceKm == null) {
            if (usesDistancePricing(cfg)) {
                return new Quote(BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP), 0d, false, false,
                        "无法计算配送距离，请确认门店与收货地址均已设置经纬度", distanceMethod);
            }
            Quote flat = quoteLegacyFlat(cfg, goodsSubtotalYuan);
            return new Quote(flat.deliveryFee, flat.distanceKm, flat.deliverable, flat.freeDelivery,
                    flat.message, distanceMethod);
        }
        distanceKm = Math.round(distanceKm * 1000d) / 1000d;

        double maxKm = cfg.getMax_delivery_distance_km() != null
                ? cfg.getMax_delivery_distance_km().doubleValue() : 5d;
        if (distanceKm > maxKm + 1e-6) {
            return new Quote(BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP), distanceKm, false, false,
                    "超出配送范围（最远 " + trimKm(maxKm) + " 公里）", distanceMethod);
        }

        BigDecimal fee = feeByTiers(cfg, distanceKm);
        boolean free = isFreeDelivery(cfg, goodsSubtotalYuan, distanceKm);
        if (free) {
            fee = BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        return new Quote(fee, distanceKm, true, free, null, distanceMethod);
    }

    private static Quote quoteLegacyFlat(ShopTakeoutConfig cfg, double goodsSubtotalYuan) {
        BigDecimal fee = cfg.getDelivery_fee() != null ? cfg.getDelivery_fee() : BigDecimal.ZERO;
        fee = fee.setScale(2, RoundingMode.HALF_UP);
        BigDecimal thr = cfg.getFree_delivery_threshold();
        if (thr != null && thr.compareTo(BigDecimal.ZERO) > 0
                && BigDecimal.valueOf(goodsSubtotalYuan).compareTo(thr) >= 0) {
            fee = BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        return new Quote(fee, 0d, true, fee.compareTo(BigDecimal.ZERO) == 0,
                "缺少门店或收货地址坐标，已按固定配送费计费", null);
    }

    public static boolean isFreeDelivery(ShopTakeoutConfig cfg, double goodsSubtotalYuan, double distanceKm) {
        if (cfg == null) {
            return false;
        }
        BigDecimal thr = cfg.getFree_delivery_threshold();
        if (thr == null || thr.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        if (BigDecimal.valueOf(goodsSubtotalYuan).compareTo(thr) < 0) {
            return false;
        }
        double freeMaxKm = cfg.getFree_delivery_max_distance_km() != null
                ? cfg.getFree_delivery_max_distance_km().doubleValue() : 5d;
        return distanceKm <= freeMaxKm + 1e-6;
    }

    public static BigDecimal feeByTiers(ShopTakeoutConfig cfg, double distanceKm) {
        List<DistanceFeeTier> tiers = parseTiers(cfg);
        tiers.sort(Comparator.comparing(t -> t.toKm != null ? t.toKm : Double.MAX_VALUE));
        for (DistanceFeeTier t : tiers) {
            if (t.toKm == null || t.fee == null) {
                continue;
            }
            if (distanceKm <= t.toKm + 1e-6) {
                return BigDecimal.valueOf(t.fee).setScale(2, RoundingMode.HALF_UP);
            }
        }
        BigDecimal fallback = cfg.getDelivery_fee() != null ? cfg.getDelivery_fee() : BigDecimal.ZERO;
        return fallback.setScale(2, RoundingMode.HALF_UP);
    }

    public static boolean usesDistancePricing(ShopTakeoutConfig cfg) {
        if (cfg == null) {
            return false;
        }
        if (cfg.getMax_delivery_distance_km() != null && cfg.getMax_delivery_distance_km().compareTo(BigDecimal.ZERO) > 0) {
            return true;
        }
        String json = cfg.getDelivery_fee_tiers_json();
        return json != null && !json.trim().isEmpty();
    }

    public static List<DistanceFeeTier> parseTiers(ShopTakeoutConfig cfg) {
        String json = cfg != null ? cfg.getDelivery_fee_tiers_json() : null;
        if (json == null || json.trim().isEmpty()) {
            json = DEFAULT_TIERS_JSON;
        }
        try {
            List<DistanceFeeTier> list = MAPPER.readValue(json.trim(), TIER_LIST);
            return list != null ? list : new ArrayList<>();
        } catch (Exception e) {
            try {
                return MAPPER.readValue(DEFAULT_TIERS_JSON, TIER_LIST);
            } catch (Exception ex) {
                return new ArrayList<>();
            }
        }
    }

    /**
     * 门店与用户地址球面距离（公里）；任一方缺坐标返回 null。
     */
    public static Double resolveDistanceKm(Shop shop, UserAddress address) {
        if (shop == null || address == null) {
            return null;
        }
        if (shop.getLatitude() == null || shop.getLongitude() == null
                || address.getLat() == null || address.getLng() == null) {
            return null;
        }
        double lat1 = shop.getLatitude().doubleValue();
        double lon1 = shop.getLongitude().doubleValue();
        double lat2 = address.getLat().doubleValue();
        double lon2 = address.getLng().doubleValue();
        return haversineKm(lat1, lon1, lat2, lon2);
    }

    /** Haversine，地球半径 6371km */
    public static double haversineKm(double lat1, double lon1, double lat2, double lon2) {
        double r = 6371.0;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return r * c;
    }

    private static String trimKm(double km) {
        if (Math.abs(km - Math.rint(km)) < 1e-6) {
            return String.valueOf((long) Math.rint(km));
        }
        return BigDecimal.valueOf(km).stripTrailingZeros().toPlainString();
    }
}
