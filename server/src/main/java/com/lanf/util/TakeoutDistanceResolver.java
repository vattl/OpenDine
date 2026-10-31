package com.lanf.util;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.lanf.config.AmapRouteProperties;
import com.lanf.entity.Shop;
import com.lanf.entity.UserAddress;
import com.lanf.integration.amap.AmapDirectionClient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

/**
 * 外卖配送距离：优先高德路网，失败或未配置 Key 时回退直线距离。
 */
@Component
public class TakeoutDistanceResolver {

    public static final String METHOD_ROUTE = "route";
    public static final String METHOD_STRAIGHT_LINE = "straight_line";

    public static final class Result {
        public final Double distanceKm;
        public final String distanceMethod;

        public Result(Double distanceKm, String distanceMethod) {
            this.distanceKm = distanceKm;
            this.distanceMethod = distanceMethod;
        }
    }

    @Autowired
    private AmapRouteProperties amapRouteProperties;
    @Autowired
    private AmapDirectionClient amapDirectionClient;

    private Cache<String, Result> routeCache;

    private Cache<String, Result> cache() {
        if (routeCache == null) {
            int minutes = Math.max(1, amapRouteProperties.getRouteCacheMinutes());
            routeCache = Caffeine.newBuilder()
                    .expireAfterWrite(minutes, TimeUnit.MINUTES)
                    .maximumSize(5000)
                    .build();
        }
        return routeCache;
    }

    public Result resolve(Shop shop, UserAddress address) {
        if (shop == null || address == null) {
            return new Result(null, null);
        }
        if (shop.getLatitude() == null || shop.getLongitude() == null
                || address.getLat() == null || address.getLng() == null) {
            return new Result(null, null);
        }
        double lat1 = shop.getLatitude().doubleValue();
        double lon1 = shop.getLongitude().doubleValue();
        double lat2 = address.getLat().doubleValue();
        double lon2 = address.getLng().doubleValue();

        if (amapRouteProperties.isRouteDistanceEnabled() && amapRouteProperties.hasWebKey()) {
            String mode = amapRouteProperties.getRouteMode() != null
                    ? amapRouteProperties.getRouteMode().trim().toLowerCase() : "driving";
            String cacheKey = cacheKey(shop.getId(), lon1, lat1, lon2, lat2, mode);
            Result cached = cache().getIfPresent(cacheKey);
            if (cached != null) {
                return cached;
            }
            Double routeKm = amapDirectionClient.routeDistanceKm(lon1, lat1, lon2, lat2);
            if (routeKm != null && routeKm >= 0) {
                Result r = new Result(round3(routeKm), METHOD_ROUTE);
                cache().put(cacheKey, r);
                return r;
            }
        }

        if (amapRouteProperties.isFallbackStraightLine() || !amapRouteProperties.hasWebKey()) {
            Double straight = TakeoutDeliveryFeeCalculator.haversineKm(lat1, lon1, lat2, lon2);
            return new Result(round3(straight), METHOD_STRAIGHT_LINE);
        }
        return new Result(null, null);
    }

    private static String cacheKey(Integer shopId, double oLng, double oLat, double dLng, double dLat, String mode) {
        return (shopId != null ? shopId : 0) + "|"
                + round4(oLng) + "," + round4(oLat) + "|"
                + round4(dLng) + "," + round4(dLat) + "|"
                + mode;
    }

    private static double round4(double v) {
        return Math.round(v * 10000d) / 10000d;
    }

    private static double round3(double v) {
        return Math.round(v * 1000d) / 1000d;
    }
}
