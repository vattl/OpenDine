package com.lanf.order;

import org.springframework.util.StringUtils;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class OrderDetailQuantityParser {

    private static final Pattern DIGIT = Pattern.compile("(\\d+)");

    private OrderDetailQuantityParser() {
    }

    public static int parsePositive(String quantityRaw) {
        if (!StringUtils.hasText(quantityRaw)) {
            throw new IllegalArgumentException("数量为空或非法");
        }
        Matcher m = DIGIT.matcher(quantityRaw.trim());
        if (!m.find()) {
            throw new IllegalArgumentException("数量格式非法：" + quantityRaw.trim());
        }
        int n = Integer.parseInt(m.group(1));
        if (n <= 0) {
            throw new IllegalArgumentException("数量须为正整数");
        }
        return n;
    }

    public static int parseQuantityOrZero(String quantityRaw) {
        if (!StringUtils.hasText(quantityRaw)) {
            return 0;
        }
        try {
            return parsePositive(quantityRaw);
        } catch (IllegalArgumentException e) {
            return 0;
        }
    }
}
