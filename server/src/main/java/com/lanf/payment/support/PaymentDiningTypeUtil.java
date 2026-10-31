package com.lanf.payment.support;

import org.springframework.util.StringUtils;

/** 就餐方式判断（支付成功后副作用用，与 OC 一致）。 */
public final class PaymentDiningTypeUtil {

    private PaymentDiningTypeUtil() {
    }

    public static boolean isWaimaiType(String raw) {
        if (!StringUtils.hasText(raw)) {
            return false;
        }
        String t = raw.trim();
        return "外卖".equals(t) || "delivery".equalsIgnoreCase(t) || "waimai".equalsIgnoreCase(t);
    }

    public static boolean isTakeOutType(String raw) {
        return "take_out".equals(normalizeDiningType(raw));
    }

    public static boolean isPackOrDeliveryType(String raw) {
        return isTakeOutType(raw) || isWaimaiType(raw);
    }

    private static String normalizeDiningType(String raw) {
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        String t = raw.trim();
        if ("堂食".equals(t) || "dine_in".equalsIgnoreCase(t) || "dinein".equalsIgnoreCase(t)) {
            return "dine_in";
        }
        if ("打包".equals(t) || "take_out".equalsIgnoreCase(t) || "takeout".equalsIgnoreCase(t)
                || "自提".equals(t) || "打包自提".equals(t) || "pickup".equalsIgnoreCase(t)
                || "pick_up".equalsIgnoreCase(t) || "pack".equalsIgnoreCase(t)) {
            return "take_out";
        }
        return t.toLowerCase();
    }
}
