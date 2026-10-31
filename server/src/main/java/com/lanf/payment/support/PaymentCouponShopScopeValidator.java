package com.lanf.payment.support;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Coupon;
import org.springframework.util.StringUtils;

import java.util.Collections;
import java.util.Set;

/** 优惠券适用门店校验（与 {@code OrderController#validateCouponShopScope} 一致）。 */
public final class PaymentCouponShopScopeValidator {

    private PaymentCouponShopScopeValidator() {
    }

    public static void validate(Coupon tmpl, Integer orderShopId) {
        if (tmpl == null) {
            return;
        }
        String raw = tmpl.getApply_shop_ids();
        if (!StringUtils.hasText(raw) || "[]".equals(raw.trim())) {
            throw new RuntimeException("该优惠券未配置适用门店，暂不可使用");
        }
        Set<Integer> shops = parseJsonIntIdSet(raw);
        if (shops.isEmpty()) {
            throw new RuntimeException("该优惠券未配置适用门店，暂不可使用");
        }
        if (orderShopId == null) {
            throw new RuntimeException("该优惠券仅限指定门店使用，请先选择门店");
        }
        if (!shops.contains(orderShopId)) {
            throw new RuntimeException("该优惠券不适用于当前门店");
        }
    }

    private static Set<Integer> parseJsonIntIdSet(String json) {
        if (!StringUtils.hasText(json)) {
            return Collections.emptySet();
        }
        try {
            ObjectMapper mapper = new ObjectMapper();
            return mapper.readValue(json.trim(), new TypeReference<Set<Integer>>() {
            });
        } catch (Exception e) {
            throw new RuntimeException("配置中的 JSON 数组格式异常，请联系管理员");
        }
    }
}
