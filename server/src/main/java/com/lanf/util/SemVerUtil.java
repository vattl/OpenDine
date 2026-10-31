package com.lanf.util;

/**
 * 语义化版本（SemVer）高精度数值比对工具类。
 * 解决字典序比对（如 "2.0.10" < "2.0.2" 的错误判定）问题。
 */
public final class SemVerUtil {

    private SemVerUtil() {}

    /**
     * 比较两个版本号。
     *
     * @param v1 第一个版本号（如 "2.0.1"、"v2.0.10+build1"）
     * @param v2 第二个版本号（如 "2.1.0"）
     * @return 负数表示 v1 < v2；0 表示相等；正数表示 v1 > v2
     */
    public static int compare(String v1, String v2) {
        if (v1 == null && v2 == null) return 0;
        if (v1 == null) return -1;
        if (v2 == null) return 1;

        String s1 = cleanVersion(v1);
        String s2 = cleanVersion(v2);

        String[] parts1 = s1.split("\\.");
        String[] parts2 = s2.split("\\.");

        int maxLength = Math.max(parts1.length, parts2.length);
        for (int i = 0; i < maxLength; i++) {
            long num1 = i < parts1.length ? parseSegmentNumber(parts1[i]) : 0L;
            long num2 = i < parts2.length ? parseSegmentNumber(parts2[i]) : 0L;

            if (num1 != num2) {
                return Long.compare(num1, num2);
            }
        }
        return 0;
    }

    public static boolean isLessThan(String v1, String v2) {
        return compare(v1, v2) < 0;
    }

    public static boolean isGreaterThan(String v1, String v2) {
        return compare(v1, v2) > 0;
    }

    public static boolean isEqual(String v1, String v2) {
        return compare(v1, v2) == 0;
    }

    public static boolean isValid(String v) {
        if (v == null || v.trim().isEmpty()) return false;
        String clean = cleanVersion(v);
        return clean.matches("^\\d+(\\.\\d+)+.*$");
    }

    private static String cleanVersion(String v) {
        String s = v.trim();
        if (s.startsWith("v") || s.startsWith("V")) {
            s = s.substring(1).trim();
        }
        // 移除 + 后的构建元数据
        int plusIdx = s.indexOf('+');
        if (plusIdx >= 0) {
            s = s.substring(0, plusIdx).trim();
        }
        // 移除 - 后的预发布标签（主要版本比较取数字部分）
        int dashIdx = s.indexOf('-');
        if (dashIdx >= 0) {
            s = s.substring(0, dashIdx).trim();
        }
        return s;
    }

    private static long parseSegmentNumber(String segment) {
        if (segment == null || segment.trim().isEmpty()) {
            return 0L;
        }
        StringBuilder digits = new StringBuilder();
        for (char c : segment.trim().toCharArray()) {
            if (Character.isDigit(c)) {
                digits.append(c);
            } else {
                break;
            }
        }
        if (digits.length() == 0) {
            return 0L;
        }
        try {
            return Long.parseLong(digits.toString());
        } catch (NumberFormatException e) {
            return 0L;
        }
    }
}
