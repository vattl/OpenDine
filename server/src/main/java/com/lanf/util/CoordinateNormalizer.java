package com.lanf.util;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Locale;

/** Normalizes coordinates at system boundaries; persisted coordinates are always GCJ-02. */
public final class CoordinateNormalizer {

    public static final String GCJ02 = "gcj02";
    public static final String WGS84 = "wgs84";
    public static final String BD09 = "bd09";

    private static final double PI = Math.PI;
    private static final double AXIS = 6378245.0;
    private static final double EE = 0.00669342162296594323;

    private CoordinateNormalizer() {
    }

    public static Point toGcj02(double lat, double lng, String coordinateType) {
        validate(lat, lng);
        String type = normalizeType(coordinateType);
        if (GCJ02.equals(type)) {
            return new Point(lat, lng);
        }
        if (BD09.equals(type)) {
            return bd09ToGcj02(lat, lng);
        }
        if (WGS84.equals(type)) {
            return wgs84ToGcj02(lat, lng);
        }
        throw new IllegalArgumentException("不支持的坐标系: " + coordinateType
                + "，仅支持 gcj02、wgs84、bd09");
    }

    /** Normalizes the declared input to GCJ-02, then converts it to Baidu BD-09. */
    public static Point toBd09(double lat, double lng, String coordinateType) {
        if (BD09.equals(normalizeType(coordinateType))) {
            validate(lat, lng);
            return new Point(lat, lng);
        }
        Point gcj02 = toGcj02(lat, lng, coordinateType);
        double z = Math.sqrt(gcj02.lng * gcj02.lng + gcj02.lat * gcj02.lat)
                + 0.00002 * Math.sin(gcj02.lat * PI * 3000.0 / 180.0);
        double theta = Math.atan2(gcj02.lat, gcj02.lng)
                + 0.000003 * Math.cos(gcj02.lng * PI * 3000.0 / 180.0);
        return new Point(z * Math.sin(theta) + 0.006, z * Math.cos(theta) + 0.0065);
    }

    public static String normalizeType(String coordinateType) {
        if (coordinateType == null || coordinateType.trim().isEmpty()) {
            return GCJ02;
        }
        String type = coordinateType.trim().toLowerCase(Locale.ROOT)
                .replace("-", "").replace("_", "");
        if ("gcj02".equals(type) || "amap".equals(type) || "tencent".equals(type)) {
            return GCJ02;
        }
        if ("wgs84".equals(type) || "gps".equals(type)) {
            return WGS84;
        }
        if ("bd09".equals(type) || "baidu".equals(type)) {
            return BD09;
        }
        return type;
    }

    public static BigDecimal decimal(double value) {
        return BigDecimal.valueOf(value).setScale(6, RoundingMode.HALF_UP);
    }

    private static Point bd09ToGcj02(double bdLat, double bdLng) {
        double x = bdLng - 0.0065;
        double y = bdLat - 0.006;
        double z = Math.sqrt(x * x + y * y) - 0.00002 * Math.sin(y * PI * 3000.0 / 180.0);
        double theta = Math.atan2(y, x) - 0.000003 * Math.cos(x * PI * 3000.0 / 180.0);
        return new Point(z * Math.sin(theta), z * Math.cos(theta));
    }

    private static Point wgs84ToGcj02(double lat, double lng) {
        if (outsideChina(lat, lng)) {
            return new Point(lat, lng);
        }
        double dLat = transformLat(lng - 105.0, lat - 35.0);
        double dLng = transformLng(lng - 105.0, lat - 35.0);
        double radLat = lat / 180.0 * PI;
        double magic = Math.sin(radLat);
        magic = 1 - EE * magic * magic;
        double sqrtMagic = Math.sqrt(magic);
        dLat = (dLat * 180.0) / ((AXIS * (1 - EE)) / (magic * sqrtMagic) * PI);
        dLng = (dLng * 180.0) / (AXIS / sqrtMagic * Math.cos(radLat) * PI);
        return new Point(lat + dLat, lng + dLng);
    }

    private static boolean outsideChina(double lat, double lng) {
        return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
    }

    private static double transformLat(double x, double y) {
        double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
                + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
        ret += (20.0 * Math.sin(6.0 * x * PI) + 20.0 * Math.sin(2.0 * x * PI)) * 2.0 / 3.0;
        ret += (20.0 * Math.sin(y * PI) + 40.0 * Math.sin(y / 3.0 * PI)) * 2.0 / 3.0;
        ret += (160.0 * Math.sin(y / 12.0 * PI) + 320 * Math.sin(y * PI / 30.0)) * 2.0 / 3.0;
        return ret;
    }

    private static double transformLng(double x, double y) {
        double ret = 300.0 + x + 2.0 * y + 0.1 * x * x
                + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
        ret += (20.0 * Math.sin(6.0 * x * PI) + 20.0 * Math.sin(2.0 * x * PI)) * 2.0 / 3.0;
        ret += (20.0 * Math.sin(x * PI) + 40.0 * Math.sin(x / 3.0 * PI)) * 2.0 / 3.0;
        ret += (150.0 * Math.sin(x / 12.0 * PI) + 300.0 * Math.sin(x / 30.0 * PI)) * 2.0 / 3.0;
        return ret;
    }

    private static void validate(double lat, double lng) {
        if (!Double.isFinite(lat) || !Double.isFinite(lng)
                || lat < -90 || lat > 90 || lng < -180 || lng > 180
                || (lat == 0 && lng == 0)) {
            throw new IllegalArgumentException("经纬度无效，纬度须在 -90~90、经度须在 -180~180，且不能同时为 0");
        }
    }

    public static final class Point {
        private final double lat;
        private final double lng;

        private Point(double lat, double lng) {
            this.lat = lat;
            this.lng = lng;
        }

        public double getLat() {
            return lat;
        }

        public double getLng() {
            return lng;
        }
    }
}
