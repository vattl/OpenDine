package com.lanf.integration.util;

import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 真省钱发单前地址文案整理：缩短 keywords、拆分门牌、推断城市。
 */
public final class ZsqAddressTextHelper {

    private static final Pattern ROOM_SUFFIX = Pattern.compile(
            "((?:\\d+街)?\\d+号(?:\\d+(?:室|房))?|"
                    + "\\d+栋(?:\\d+单元)?(?:\\d+(?:室|房))?|"
                    + "\\d+单元(?:\\d+(?:室|房))?|\\d+(?:室|房))\\s*$");
    private static final Pattern DIRECTION_NOISE = Pattern.compile("(?:交叉口|路口)?(?:正)?[东南西北]+方向\\d+米左右?");
    private static final Pattern LABELED_ADDRESS_SUFFIX = Pattern.compile(
            "\\s*(?:门牌(?:号)?|配送说明|配送备注)\\s*[:：].*$");
    private static final Pattern EXPLICIT_DOORPLATE = Pattern.compile(
            "(?:门牌(?:号)?)\\s*[:：]\\s*(.+?)(?=\\s*(?:配送说明|配送备注)\\s*[:：]|$)");
    private static final Pattern DELIVERY_NOTE = Pattern.compile(
            "(?:配送说明|配送备注)\\s*[:：]\\s*(.+)$");

    private ZsqAddressTextHelper() {
    }

    /** 从用户地址拼 keywords（区 + 精简 detail），供高德 input-tips。 */
    public static String buildKeywords(String district, String detailAddress, String addressFullFallback) {
        String poiName = extractPoiName(detailAddress);
        StringBuilder sb = new StringBuilder();
        if (StringUtils.hasText(district)) {
            sb.append(district.trim());
        }
        String detail = sanitizeDetailForKeywords(detailAddress);
        if (StringUtils.hasText(detail)) {
            sb.append(detail);
        }
        if (sb.length() > 0) {
            String address = sb.toString();
            if (StringUtils.hasText(poiName) && !address.contains(poiName)) {
                address = address + "·" + poiName;
            }
            return trimKeywordLength(address);
        }
        if (StringUtils.hasText(addressFullFallback)) {
            return trimKeywordLength(sanitizeDetailForKeywords(addressFullFallback.trim()));
        }
        return "收货地址";
    }

    private static String extractPoiName(String raw) {
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        int dot = raw.indexOf('·');
        return dot > 0 ? raw.substring(0, dot).trim() : "";
    }

    /** 门牌/房号；过长 POI 描述时尽量截取末尾门牌段。 */
    public static String buildDetail(String detailAddress, String addressFullFallback) {
        if (StringUtils.hasText(detailAddress)) {
            String explicit = extractExplicitDeliveryDetail(detailAddress.trim());
            if (StringUtils.hasText(explicit)) {
                return explicit.length() > 64 ? explicit.substring(0, 64) : explicit;
            }
            String room = extractRoomSuffix(detailAddress.trim());
            if (StringUtils.hasText(room)) {
                return room;
            }
            String shortDetail = sanitizeDetailForKeywords(detailAddress.trim());
            if (StringUtils.hasText(shortDetail)) {
                return shortDetail.length() > 64 ? shortDetail.substring(0, 64) : shortDetail;
            }
        }
        if (StringUtils.hasText(addressFullFallback)) {
            String room = extractRoomSuffix(addressFullFallback.trim());
            if (StringUtils.hasText(room)) {
                return room;
            }
            return addressFullFallback.trim().length() > 64
                    ? addressFullFallback.trim().substring(0, 64) : addressFullFallback.trim();
        }
        return "门牌号";
    }

    /**
     * 解析城市：优先配置/用户 city；district 含县级市名时优先县级市（如鹤山市）。
     */
    public static String resolveCityName(String configuredCity, String userCity, String district, String defaultCity) {
        if (StringUtils.hasText(configuredCity)) {
            return normalizeCityName(configuredCity.trim());
        }
        String fromDistrict = cityFromDistrict(district);
        if (StringUtils.hasText(fromDistrict)) {
            return fromDistrict;
        }
        if (StringUtils.hasText(userCity)) {
            return normalizeCityName(userCity.trim());
        }
        return StringUtils.hasText(defaultCity) ? normalizeCityName(defaultCity.trim()) : "江门市";
    }

    /** 依次尝试的 keywords（去重、非空）。 */
    public static List<String> keywordAttempts(String primary) {
        LinkedHashSet<String> set = new LinkedHashSet<>();
        if (StringUtils.hasText(primary)) {
            addKeywordVariants(set, primary.trim());
        }
        return new ArrayList<>(set);
    }

    /** 依次尝试的城市（去重）。 */
    public static List<String> cityAttempts(String primaryCity, String district) {
        LinkedHashSet<String> set = new LinkedHashSet<>();
        if (StringUtils.hasText(primaryCity)) {
            set.add(normalizeCityName(primaryCity.trim()));
        }
        String fromDistrict = cityFromDistrict(district);
        if (StringUtils.hasText(fromDistrict)) {
            set.add(fromDistrict);
        }
        if (set.isEmpty()) {
            set.add("江门市");
        }
        return new ArrayList<>(set);
    }

    static String sanitizeDetailForKeywords(String raw) {
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        String s = raw.trim();
        int dot = s.indexOf('·');
        if (dot >= 0) {
            String left = s.substring(0, dot).trim();
            String right = s.substring(dot + 1).trim();
            s = StringUtils.hasText(right) ? right : left;
        }
        s = LABELED_ADDRESS_SUFFIX.matcher(s).replaceFirst("");
        s = DIRECTION_NOISE.matcher(s).replaceAll("");
        String room = extractRoomSuffix(s);
        if (StringUtils.hasText(room)
                && room.matches(".*(?:室|房|栋|单元).*$")) {
            s = s.substring(0, s.length() - room.length()).trim();
        }
        s = s.replaceAll("\\s+", "");
        return s.trim();
    }

    private static String extractExplicitDeliveryDetail(String raw) {
        Matcher doorplate = EXPLICIT_DOORPLATE.matcher(raw);
        Matcher note = DELIVERY_NOTE.matcher(raw);
        String doorplateText = doorplate.find() ? doorplate.group(1).trim() : "";
        String noteText = note.find() ? note.group(1).trim() : "";
        if (StringUtils.hasText(doorplateText) && StringUtils.hasText(noteText)) {
            return doorplateText + "；配送说明：" + noteText;
        }
        if (StringUtils.hasText(doorplateText)) {
            return doorplateText;
        }
        return StringUtils.hasText(noteText) ? "配送说明：" + noteText : "";
    }

    static String extractRoomSuffix(String raw) {
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        Matcher m = ROOM_SUFFIX.matcher(raw.trim());
        if (m.find()) {
            return m.group(1).trim();
        }
        return "";
    }

    static String trimKeywordLength(String s) {
        if (s == null) {
            return "";
        }
        String t = s.trim();
        return t.length() > 48 ? t.substring(0, 48) : t;
    }

    static String normalizeCityName(String city) {
        String c = city.trim();
        if (c.endsWith("市") || c.endsWith("县") || c.endsWith("区")) {
            return c;
        }
        return c + "市";
    }

    static String cityFromDistrict(String district) {
        if (!StringUtils.hasText(district)) {
            return null;
        }
        String d = district.trim();
        if (d.endsWith("市") || d.endsWith("县")) {
            return normalizeCityName(d);
        }
        if (d.contains("鹤山")) {
            return "鹤山市";
        }
        return null;
    }

    private static void addKeywordVariants(LinkedHashSet<String> set, String primary) {
        String sanitized = sanitizeDetailForKeywords(primary);
        if (StringUtils.hasText(sanitized)) {
            set.add(trimKeywordLength(sanitized));
        }
        int dot = primary.indexOf('·');
        if (dot >= 0) {
            String left = primary.substring(0, dot).trim();
            if (StringUtils.hasText(left)) {
                set.add(trimKeywordLength(sanitizeDetailForKeywords(left)));
            }
        }
        String room = extractRoomSuffix(primary);
        if (StringUtils.hasText(room) && room.length() >= 4) {
            set.add(trimKeywordLength(room));
        }
        if (StringUtils.hasText(primary) && primary.length() > 48) {
            set.add(trimKeywordLength(primary.substring(0, 48)));
        }
    }
}
