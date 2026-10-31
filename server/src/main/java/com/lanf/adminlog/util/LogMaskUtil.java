package com.lanf.adminlog.util;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 日志内容脱敏（协调文档 §1：审计字段及个人信息按调用者权限脱敏）。
 * 对手机号（大陆 11 位）、身份证号（15/18 位）正则打码；其余文本原样返回。
 * 纯静态工具，便于单元测试。
 */
public final class LogMaskUtil {

    private LogMaskUtil() {
    }

    /** 大陆手机号：保留前 3 后 4，如 138****5678 */
    private static final Pattern MOBILE = Pattern.compile("(?<!\\d)(1[3-9]\\d)\\d{4}(\\d{4})(?!\\d)");

    /** 18 位身份证：保留前 3 后 4（末位可为 X/x） */
    private static final Pattern ID_CARD_18 = Pattern.compile("(?<!\\d)(\\d{3})\\d{11}(\\d{4})(?!\\d)");

    /** 18 位身份证末位为 X/x（17 位数字 + 校验位）：保留前 3 后 4 */
    private static final Pattern ID_CARD_17X = Pattern.compile("(?<!\\d)(\\d{3})\\d{11}(\\d{3}[Xx])(?!\\d)");

    /** 15 位身份证：保留前 3 后 4 */
    private static final Pattern ID_CARD_15 = Pattern.compile("(?<!\\d)(\\d{3})\\d{8}(\\d{4})(?!\\d)");

    /** JSON 中不得进入审计快照的凭据字段，支持转义后的字符串值。 */
    private static final Pattern JSON_SECRET = Pattern.compile(
            "(?i)(\\\"(?:password|newPassword|new_password|token|secret)\\\"\\s*:\\s*\\\")((?:\\\\.|[^\\\"\\\\])*)(\\\")");

    /** 对文本中的手机号/身份证号打码；null 原样返回 */
    public static String mask(String text) {
        if (text == null || text.isEmpty()) {
            return text;
        }
        String out = maskJsonSecrets(text);
        out = maskId18(out);
        out = mask17x(out);
        out = maskId15(out);
        return maskMobile(out);
    }

    private static String maskJsonSecrets(String s) {
        Matcher m = JSON_SECRET.matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            m.appendReplacement(sb, Matcher.quoteReplacement(m.group(1) + "****" + m.group(3)));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    private static String mask17x(String s) {
        Matcher m = ID_CARD_17X.matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            m.appendReplacement(sb, Matcher.quoteReplacement(m.group(1) + "***********" + m.group(2)));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    private static String maskId18(String s) {
        Matcher m = ID_CARD_18.matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            m.appendReplacement(sb, Matcher.quoteReplacement(m.group(1) + "***********" + m.group(2)));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    private static String maskId15(String s) {
        Matcher m = ID_CARD_15.matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            m.appendReplacement(sb, Matcher.quoteReplacement(m.group(1) + "********" + m.group(2)));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    private static String maskMobile(String s) {
        Matcher m = MOBILE.matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            m.appendReplacement(sb, Matcher.quoteReplacement(m.group(1) + "****" + m.group(2)));
        }
        m.appendTail(sb);
        return sb.toString();
    }
}
