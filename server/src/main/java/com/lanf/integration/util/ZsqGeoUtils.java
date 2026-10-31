package com.lanf.integration.util;

import com.lanf.util.CoordinateNormalizer;

/**
 * 地理距离与 ETA 估算（Haversine，地球半径 6371km）。
 */
public final class ZsqGeoUtils {

    private ZsqGeoUtils() {
    }

    public static Double parseCoord(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number) {
            return ((Number) value).doubleValue();
        }
        String s = String.valueOf(value).trim();
        if (s.isEmpty()) {
            return null;
        }
        try {
            return Double.parseDouble(s);
        } catch (NumberFormatException e) {
            return null;
        }
    }

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

    public static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
        return haversineKm(lat1, lon1, lat2, lon2) * 1000.0;
    }

    /**
     * 百度 BD-09 → 高德/腾讯 GCJ-02（真省钱发单店铺坐标 → 本系统 t_shop 坐标系）。
     */
    public static double[] bd09ToGcj02(double bdLat, double bdLng) {
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                bdLat, bdLng, CoordinateNormalizer.BD09);
        return new double[]{point.getLat(), point.getLng()};
    }

  /** 根据距离（公里）与速度（km/h）估算分钟数，至少 1 分钟。 */
    public static int etaMinutes(double distanceKm, double speedKmh) {
        if (distanceKm <= 0 || speedKmh <= 0) {
            return 0;
        }
        int minutes = (int) Math.ceil(distanceKm / speedKmh * 60.0);
        return Math.max(minutes, 1);
    }
}
