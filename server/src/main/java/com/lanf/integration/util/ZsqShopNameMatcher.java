package com.lanf.integration.util;

import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.dto.ZsqShopAddress;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * 本系统门店中文名 + 坐标 ↔ 真省钱发单店铺匹配。
 */
public final class ZsqShopNameMatcher {

    /** 店名匹配后，定位校验允许的最大偏差（米） */
    public static final double MAX_LOCATION_MATCH_METERS = 50.0;

    private ZsqShopNameMatcher() {
    }

    public static String normalize(String name) {
        if (name == null) {
            return "";
        }
        return name.trim().replaceAll("[\\s\\u3000]+", "");
    }

    /**
     * 按店名在真省钱发单店铺列表中匹配；无匹配返回 null。
     */
    public static ZsqShopAddress pickByShopName(List<ZsqShopAddress> shops, String localShopName) {
        return pickByShopName(shops, localShopName, null, null);
    }

    /**
     * 按店名匹配，并在提供本系统坐标时校验与真省钱发单店铺坐标偏差 ≤ {@link #MAX_LOCATION_MATCH_METERS} 米。
     */
    public static ZsqShopAddress pickByShopName(List<ZsqShopAddress> shops, String localShopName,
                                                Double localLat, Double localLng) {
        if (shops == null || shops.isEmpty()) {
            return null;
        }
        String normalized = normalize(localShopName);
        if (normalized.isEmpty()) {
            return null;
        }
        List<ZsqShopAddress> byName = findByShopName(shops, normalized);
        if (byName.isEmpty()) {
            return null;
        }
        return resolveWithLocationCheck(localShopName, byName, localLat, localLng);
    }

    private static List<ZsqShopAddress> findByShopName(List<ZsqShopAddress> shops, String normalized) {
        List<ZsqShopAddress> exact = shops.stream()
                .filter(s -> normalized.equals(normalize(s.getShopName())))
                .collect(Collectors.toList());
        if (!exact.isEmpty()) {
            return exact;
        }

        List<ZsqShopAddress> fuzzy = new ArrayList<>();
        for (ZsqShopAddress shop : shops) {
            String zsqName = normalize(shop.getShopName());
            if (zsqName.isEmpty()) {
                continue;
            }
            if (zsqName.contains(normalized) || normalized.contains(zsqName)) {
                fuzzy.add(shop);
            }
        }
        return fuzzy;
    }

    private static ZsqShopAddress resolveWithLocationCheck(String localShopName,
                                                           List<ZsqShopAddress> candidates,
                                                           Double localLat, Double localLng) {
        if (localLat == null || localLng == null) {
            if (candidates.size() == 1) {
                return candidates.get(0);
            }
            throw ambiguous(localShopName, candidates);
        }

        List<ZsqShopAddress> within = candidates.stream()
                .filter(s -> isWithinDistanceMeters(localLat, localLng, s, MAX_LOCATION_MATCH_METERS))
                .collect(Collectors.toList());
        if (within.isEmpty()) {
            if (candidates.size() == 1) {
                throw locationMismatch(localShopName, candidates.get(0), localLat, localLng);
            }
            throw new ZsqApiException("店名「" + localShopName + "」匹配到多家真省钱发单店铺，且均在"
                    + (int) MAX_LOCATION_MATCH_METERS + "米外");
        }
        if (within.size() == 1) {
            return within.get(0);
        }
        throw ambiguous(localShopName, within);
    }

    static boolean isWithinDistanceMeters(double localLat, double localLng, ZsqShopAddress zsq, double maxMeters) {
        double[] gcj = resolveZsqGcj02Coords(zsq);
        if (gcj == null) {
            return false;
        }
        return ZsqGeoUtils.haversineMeters(localLat, localLng, gcj[0], gcj[1]) <= maxMeters;
    }

    private static double[] resolveZsqGcj02Coords(ZsqShopAddress zsq) {
        Double bdLat = ZsqGeoUtils.parseCoord(zsq.getShopLat());
        Double bdLng = ZsqGeoUtils.parseCoord(zsq.getShopLng());
        if (bdLat == null || bdLng == null) {
            return null;
        }
        return ZsqGeoUtils.bd09ToGcj02(bdLat, bdLng);
    }

    private static ZsqApiException locationMismatch(String localShopName, ZsqShopAddress zsq,
                                                    double localLat, double localLng) {
        double[] gcj = resolveZsqGcj02Coords(zsq);
        String distanceHint = "";
        if (gcj != null) {
            int meters = (int) Math.round(ZsqGeoUtils.haversineMeters(localLat, localLng, gcj[0], gcj[1]));
            distanceHint = "，偏差约 " + meters + " 米（真省钱 BD-09 已换算 GCJ-02）";
        } else {
            distanceHint = "，真省钱发单店铺缺少坐标";
        }
        return new ZsqApiException("店名「" + localShopName + "」已匹配真省钱店铺「" + zsq.getShopName()
                + "」(id=" + zsq.getId() + ")，但定位偏差超过 " + (int) MAX_LOCATION_MATCH_METERS + " 米"
                + distanceHint + "，请核对 t_shop 坐标或配置 zsq_from_address_id");
    }

    private static ZsqApiException ambiguous(String localShopName, List<ZsqShopAddress> matched) {
        String names = matched.stream()
                .map(s -> s.getShopName() + "(id=" + s.getId() + ")")
                .collect(Collectors.joining("、"));
        return new ZsqApiException("店名「" + localShopName + "」匹配到多家真省钱发单店铺：" + names);
    }
}
