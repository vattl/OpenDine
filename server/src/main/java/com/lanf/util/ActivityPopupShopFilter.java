package com.lanf.util;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * 活动弹窗 {@code apply_shop_ids}（JSON 数组，如 {@code [1,5,3]}）与当前门店是否匹配。
 */
public final class ActivityPopupShopFilter {

    private static final ObjectMapper OM = new ObjectMapper();

    private ActivityPopupShopFilter() {
    }

    /** NULL、空串、{@code []} 表示全部门店可见 */
    public static boolean isGlobalScope(String applyShopIdsRaw) {
        if (applyShopIdsRaw == null) {
            return true;
        }
        String raw = applyShopIdsRaw.trim();
        return raw.isEmpty() || "[]".equals(raw);
    }

    /**
     * @param shopId 当前门店；为 null 时仅返回 {@link #isGlobalScope} 为 true 的活动
     */
    public static boolean appliesToShop(String applyShopIdsRaw, Integer shopId) {
        if (isGlobalScope(applyShopIdsRaw)) {
            return true;
        }
        if (shopId == null || shopId <= 0) {
            return false;
        }
        try {
            JsonNode node = OM.readTree(applyShopIdsRaw.trim());
            if (!node.isArray()) {
                return false;
            }
            for (JsonNode n : node) {
                if (n.isNumber() && n.intValue() == shopId) {
                    return true;
                }
                if (n.isTextual()) {
                    try {
                        if (Integer.parseInt(n.asText().trim()) == shopId) {
                            return true;
                        }
                    } catch (NumberFormatException ignored) {
                    }
                }
            }
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    /** 写入库前规范化：null/空 → null（全部门店）；合法 JSON 数组原样 trim */
    public static String normalizeForSave(String applyShopIdsRaw) {
        if (applyShopIdsRaw == null) {
            return null;
        }
        String raw = applyShopIdsRaw.trim();
        if (raw.isEmpty() || "[]".equals(raw)) {
            return null;
        }
        try {
            JsonNode node = OM.readTree(raw);
            if (!node.isArray()) {
                throw new IllegalArgumentException("apply_shop_ids 须为 JSON 数组，如 [1,5,3]");
            }
            return OM.writeValueAsString(node);
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("apply_shop_ids 格式无效，须为 JSON 数组，如 [1,5,3]");
        }
    }
}
