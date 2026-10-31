package com.lanf.integration.util;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 从真省钱取消接口响应中解析责任扣费（元）。
 */
public final class ZsqLiabilityFeeParser {

    private static final String[] MONEY_KEYS = {
            "liabilityFee", "responsibilityFee", "responsibleFee", "deductMoney", "deductFee",
            "cancelFee", "needPayMoney", "payMoney", "deductionAmount", "cancelAmount",
            "breachFee", "compensationFee", "dutyFee", "dutyAmount", "penaltyFee"
    };

    private static final Pattern PROMPT_MONEY = Pattern.compile(
            "(?:责任费|扣费|扣除|需支付|应付|违约金|补偿)[^0-9]{0,12}(\\d+(?:\\.\\d+)?)\\s*元");

    private ZsqLiabilityFeeParser() {
    }

    public static BigDecimal parseFromMaps(Map<String, Object>... maps) {
        BigDecimal max = BigDecimal.ZERO;
        if (maps != null) {
            for (Map<String, Object> map : maps) {
                BigDecimal v = parseFromMap(map);
                if (v != null && v.compareTo(max) > 0) {
                    max = v;
                }
            }
        }
        return max.compareTo(BigDecimal.ZERO) > 0 ? max : null;
    }

    public static BigDecimal parseFromPromptText(String cancelPrompt) {
        if (cancelPrompt == null || cancelPrompt.trim().isEmpty()) {
            return null;
        }
        Matcher m = PROMPT_MONEY.matcher(cancelPrompt);
        BigDecimal max = null;
        while (m.find()) {
            BigDecimal v = toMoney(m.group(1));
            if (v != null && (max == null || v.compareTo(max) > 0)) {
                max = v;
            }
        }
        return max;
    }

    public static BigDecimal merge(BigDecimal a, BigDecimal b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return a.compareTo(b) >= 0 ? a : b;
    }

    @SuppressWarnings("unchecked")
    private static BigDecimal parseFromMap(Map<String, Object> map) {
        if (map == null || map.isEmpty()) {
            return null;
        }
        BigDecimal max = null;
        for (String key : MONEY_KEYS) {
            BigDecimal v = toMoney(map.get(key));
            if (v != null && (max == null || v.compareTo(max) > 0)) {
                max = v;
            }
        }
        Object prompt = map.get("cancelPrompt");
        if (prompt != null) {
            BigDecimal fromText = parseFromPromptText(String.valueOf(prompt));
            max = merge(max, fromText);
        }
        Object data = map.get("data");
        if (data instanceof Map) {
            BigDecimal nested = parseFromMap((Map<String, Object>) data);
            max = merge(max, nested);
        }
        return max;
    }

    private static BigDecimal toMoney(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number) {
            return BigDecimal.valueOf(((Number) value).doubleValue()).setScale(2, RoundingMode.HALF_UP);
        }
        String s = String.valueOf(value).trim();
        if (s.isEmpty()) {
            return null;
        }
        s = s.replace("元", "").replace("￥", "").replace(",", "").trim();
        try {
            return new BigDecimal(s).setScale(2, RoundingMode.HALF_UP);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
