package com.lanf.util;

import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;
import java.util.function.Function;

/**
 * 连锁门店上下文：X-Shop-Id / X-Shop-Code 与 body、query 中 shop_id / shop_code 的解析与合并（与 docs/openapi.yaml、admin_chain_permission_architecture.md 一致）。
 * 优先级：请求头 ID → 请求头 Code → body/query ID → body/query Code；同层 ID 与 Code 同时出现时须指向同一营业门店。
 */
public final class ShopChainSupport {

    private ShopChainSupport() {}

    public static Integer parseHeaderShopId(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        String h = request.getHeader("X-Shop-Id");
        if (!StringUtils.hasText(h)) {
            return null;
        }
        try {
            return Integer.parseInt(h.trim());
        } catch (NumberFormatException e) {
            throw new RuntimeException("请求头 X-Shop-Id 无效");
        }
    }

    /**
     * 请求头 {@code X-Shop-Code}，trim 后空则 null。
     */
    public static String parseHeaderShopCode(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        String h = request.getHeader("X-Shop-Code");
        if (!StringUtils.hasText(h)) {
            return null;
        }
        return h.trim();
    }

    public static Integer parseBodyShopId(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Number) {
            return ((Number) raw).intValue();
        }
        String s = raw.toString().trim();
        if (s.isEmpty()) {
            return null;
        }
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            throw new RuntimeException("参数 shop_id 无效");
        }
    }

    /**
     * Body / query 中的 {@code shop_code} 字符串，trim 后空则 null。
     */
    public static String parseBodyShopCode(Object raw) {
        if (raw == null) {
            return null;
        }
        String s = raw.toString().trim();
        return s.isEmpty() ? null : s;
    }

    /**
     * 同一来源（仅 header 或仅 body）下，shop_id 与 shop_code 同时存在时必须解析为同一门店。
     *
     * @param codeToActiveShopId 将非空 code 转为营业中门店 id；不可为 null（当 shopCode 非空时）
     */
    public static Integer mergeShopIdFromIdAndCode(Integer shopId, String shopCode,
                                                     Function<String, Integer> codeToActiveShopId) {
        Integer fromCode = null;
        if (StringUtils.hasText(shopCode)) {
            if (codeToActiveShopId == null) {
                throw new IllegalStateException("门店编码解析器未配置");
            }
            fromCode = codeToActiveShopId.apply(shopCode.trim());
        }
        if (shopId != null && fromCode != null && !shopId.equals(fromCode)) {
            throw new RuntimeException("门店信息不一致，请检查门店 ID 与门店编码是否指向同一营业门店");
        }
        return shopId != null ? shopId : fromCode;
    }

    /**
     * 合并 header 侧与 body 侧的门店，二者同时存在时必须一致。
     */
    public static Integer resolveShopChain(HttpServletRequest request, Integer bodyShopId, String bodyShopCode,
                                           Function<String, Integer> codeToActiveShopId) {
        Integer headerMerged = mergeShopIdFromIdAndCode(parseHeaderShopId(request), parseHeaderShopCode(request),
                codeToActiveShopId);
        Integer bodyMerged = mergeShopIdFromIdAndCode(bodyShopId, bodyShopCode, codeToActiveShopId);
        return resolveShopId(headerMerged, bodyMerged);
    }

    /**
     * Header 与 body 同时存在时必须相等；否则抛业务异常。
     */
    public static Integer resolveShopId(Integer headerShopId, Integer bodyShopId) {
        if (headerShopId != null && bodyShopId != null && !headerShopId.equals(bodyShopId)) {
            throw new RuntimeException("门店信息不一致，请检查请求头（X-Shop-Id / X-Shop-Code）与参数 shop_id / shop_code");
        }
        return headerShopId != null ? headerShopId : bodyShopId;
    }

    /**
     * 与 {@link #resolveShopChain} 类似，但 body/query 参数优先于请求头。
     * 用于「按订单/指定门店查询」场景：调用方显式传入的 shop_id/shop_code 应覆盖设备默认的 X-Shop-Id。
     */
    public static Integer resolveShopChainPreferParam(HttpServletRequest request, Integer bodyShopId, String bodyShopCode,
                                                      Function<String, Integer> codeToActiveShopId) {
        Integer bodyMerged = mergeShopIdFromIdAndCode(bodyShopId, bodyShopCode, codeToActiveShopId);
        if (bodyMerged != null) {
            return bodyMerged;
        }
        return mergeShopIdFromIdAndCode(parseHeaderShopId(request), parseHeaderShopCode(request), codeToActiveShopId);
    }
}
