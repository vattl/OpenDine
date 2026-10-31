package com.lanf.payment.support;

import com.lanf.entity.R;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * C 端微信充值固定「充送」档位校验（与 {@code OrderController} 原逻辑一致）。
 */
public final class WxRechargeGiftTierValidator {

    public static final double MIN_YUAN = 50.00d;
    public static final double MAX_YUAN = 10000.00d;

    private static final Map<BigDecimal, BigDecimal> GIFT_TIERS = giftTierMap();

    private WxRechargeGiftTierValidator() {
    }

    private static Map<BigDecimal, BigDecimal> giftTierMap() {
        Map<BigDecimal, BigDecimal> m = new LinkedHashMap<>();
        m.put(new BigDecimal("200.00"), new BigDecimal("10.00"));
        m.put(new BigDecimal("500.00"), new BigDecimal("50.00"));
        m.put(new BigDecimal("1000.00"), new BigDecimal("120.00"));
        m.put(new BigDecimal("5000.00"), new BigDecimal("750.00"));
        m.put(new BigDecimal("10000.00"), new BigDecimal("2000.00"));
        return Collections.unmodifiableMap(m);
    }

    /** @return 校验通过返回 null，否则返回 R.error */
    public static R validate(BigDecimal rechargeBd, BigDecimal giftBd) {
        if (giftBd == null || giftBd.compareTo(BigDecimal.ZERO) <= 0) {
            return null;
        }
        BigDecimal expected = GIFT_TIERS.get(rechargeBd);
        if (expected == null) {
            return R.error("非活动档位不能使用赠送金额，活动本金为：200 / 500 / 1000 / 5000 / 10000 元");
        }
        if (giftBd.compareTo(expected) != 0) {
            return R.error(String.format(
                    "赠送金额与活动规则不符：充值 %s 元应送 %s 元（当前赠送 %s 元）",
                    rechargeBd.toPlainString(), expected.toPlainString(), giftBd.toPlainString()));
        }
        return null;
    }
}
