package com.lanf.util;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Coupon;

/**
 * 优惠券 {@link Coupon#getApply_shop_ids}（JSON 数组）与当前门店是否匹配。
 */
public final class CouponShopFilter {

    private static final ObjectMapper OM = new ObjectMapper();

    private CouponShopFilter() {
    }

    /**
     * @param shopId 当前门店；为 null 时不做门店限制（视为通过）
     */
    public static boolean appliesToShop(Coupon c, Integer shopId) {
        if (shopId == null || c == null) {
            return true;
        }
        String raw = c.getApply_shop_ids();
        if (raw == null || raw.trim().isEmpty()) {
            return true;
        }
        try {
            JsonNode node = OM.readTree(raw.trim());
            if (!node.isArray()) {
                return false;
            }
            for (JsonNode n : node) {
                if (n.isInt() && n.asInt() == shopId) {
                    return true;
                }
                if (n.isIntegralNumber() && n.intValue() == shopId) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 与小程序「当前门店可用券」列表一致：{@code apply_shop_ids} 须为包含 {@code shopId} 的<strong>非空</strong> JSON 数组；
     * 空、NULL、{@code []} 视为<strong>不适用</strong>当前门店（与 {@link #appliesToShop} 的「空=全部门店」不同）。
     */
    public static boolean strictShopScope(String applyShopIdsRaw, Integer shopId) {
        if (shopId == null || shopId <= 0) {
            return false;
        }
        if (applyShopIdsRaw == null || applyShopIdsRaw.trim().isEmpty()) {
            return false;
        }
        String raw = applyShopIdsRaw.trim();
        if ("[]".equals(raw)) {
            return false;
        }
        try {
            JsonNode node = OM.readTree(raw);
            if (!node.isArray() || node.size() == 0) {
                return false;
            }
            for (JsonNode n : node) {
                if (n.isInt() && n.asInt() == shopId) {
                    return true;
                }
                if (n.isIntegralNumber() && n.intValue() == shopId) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            return false;
        }
    }
}
