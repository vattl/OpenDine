package com.lanf.kds.support;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

/**
 * 订单明细规格 JSON（selectedSpicy）规范化，用于合并键比对。
 * <p>合并相同菜品时按<strong>规格</strong>与<strong>口味</strong>维度拆分键。</p>
 */
public final class KdsSpecNormalizer {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private KdsSpecNormalizer() {
    }

    public static final class SpecTastePair {
        private final String specNorm;
        private final String tasteNorm;

        public SpecTastePair(String specNorm, String tasteNorm) {
            this.specNorm = specNorm != null ? specNorm : "";
            this.tasteNorm = tasteNorm != null ? tasteNorm : "";
        }

        public String getSpecNorm() {
            return specNorm;
        }

        public String getTasteNorm() {
            return tasteNorm;
        }
    }

    /** 无规格或解析失败时返回空串（与空规格视为同一类）。合并展示用，含规格+口味全量键。 */
    public static String normalize(String selectedSpicy) {
        SpecTastePair pair = splitSpecAndTaste(selectedSpicy, null);
        return joinSpecTaste(pair.getSpecNorm(), pair.getTasteNorm());
    }

    /**
     * 将 selectedSpicy 拆为规格键与口味键，供「同菜名+同规格+同口味」合并。
     *
     * @param dishSpecification 菜品模板 JSON（t_dish.specification），可为 null
     */
    public static SpecTastePair splitSpecAndTaste(String selectedSpicy, String dishSpecification) {
        Map<String, String> selected = parseSelectedMap(selectedSpicy);
        if (selected.isEmpty()) {
            return new SpecTastePair("", "");
        }
        Set<String> dishGroups = parseDishGroupKeys(dishSpecification);
        TreeMap<String, String> spec = new TreeMap<>();
        TreeMap<String, String> taste = new TreeMap<>();
        for (Map.Entry<String, String> e : selected.entrySet()) {
            if (isTasteGroup(e.getKey(), dishGroups)) {
                taste.put(e.getKey(), e.getValue());
            } else {
                spec.put(e.getKey(), e.getValue());
            }
        }
        return new SpecTastePair(canonMap(spec), canonMap(taste));
    }

    private static String joinSpecTaste(String spec, String taste) {
        if (!StringUtils.hasText(spec)) {
            return taste != null ? taste : "";
        }
        if (!StringUtils.hasText(taste)) {
            return spec;
        }
        return spec + '|' + taste;
    }

    private static Map<String, String> parseSelectedMap(String selectedSpicy) {
        if (!StringUtils.hasText(selectedSpicy)) {
            return new TreeMap<>();
        }
        String trimmed = selectedSpicy.trim();
        if ("null".equalsIgnoreCase(trimmed)) {
            return new TreeMap<>();
        }
        try {
            Map<String, Object> raw = MAPPER.readValue(trimmed, new TypeReference<Map<String, Object>>() {});
            TreeMap<String, String> canon = new TreeMap<>();
            for (Map.Entry<String, Object> e : raw.entrySet()) {
                if (e.getKey() == null) {
                    continue;
                }
                String values = flattenValue(e.getValue());
                if (StringUtils.hasText(values)) {
                    canon.put(e.getKey().trim(), values);
                }
            }
            return canon;
        } catch (Exception ex) {
            TreeMap<String, String> fallback = new TreeMap<>();
            fallback.put("_raw", trimmed);
            return fallback;
        }
    }

    private static Set<String> parseDishGroupKeys(String dishSpecification) {
        Set<String> keys = new LinkedHashSet<>();
        if (!StringUtils.hasText(dishSpecification)) {
            return keys;
        }
        try {
            Map<String, Object> raw = MAPPER.readValue(dishSpecification.trim(), new TypeReference<Map<String, Object>>() {});
            for (String k : raw.keySet()) {
                if (k != null && StringUtils.hasText(k)) {
                    keys.add(k.trim());
                }
            }
        } catch (Exception ignore) {
            // ignore malformed template
        }
        return keys;
    }

    private static boolean isTasteGroup(String groupKey, Set<String> dishGroups) {
        if (!StringUtils.hasText(groupKey)) {
            return false;
        }
        String key = groupKey.trim();
        String lower = key.toLowerCase(Locale.ROOT);
        if (containsAny(lower, key, "辣", "口味", "甜", "糖", "温", "冰", "咸", "酸", "忌", "葱", "蒜", "姜", "香菜")) {
            return true;
        }
        if (containsAny(lower, key, "规格", "份量", "大小", "尺寸", "份", "单位", "其他", "熟")) {
            return false;
        }
        if (!dishGroups.isEmpty()) {
            return dishGroups.contains(key)
                    && containsAny(lower, key, "辣", "口味", "甜", "糖", "温", "冰");
        }
        return true;
    }

    private static boolean containsAny(String lower, String original, String... needles) {
        for (String n : needles) {
            if (lower.contains(n) || original.contains(n)) {
                return true;
            }
        }
        return false;
    }

    private static String canonMap(TreeMap<String, String> canon) {
        if (canon.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : canon.entrySet()) {
            if (sb.length() > 0) {
                sb.append('|');
            }
            sb.append(e.getKey()).append('=').append(e.getValue());
        }
        return sb.toString();
    }

    private static String flattenValue(Object val) {
        if (val == null) {
            return "";
        }
        if (val instanceof List) {
            List<String> parts = new ArrayList<>();
            for (Object o : (List<?>) val) {
                if (o != null) {
                    String s = o.toString().trim();
                    if (!s.isEmpty()) {
                        parts.add(s);
                    }
                }
            }
            parts.sort(String::compareTo);
            return String.join(",", parts);
        }
        return val.toString().trim();
    }
}
