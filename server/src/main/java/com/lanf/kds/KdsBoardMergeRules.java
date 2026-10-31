package com.lanf.kds;

import com.lanf.kds.entity.KdsShopConfig;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * 工作流看板合并规则。
 * <p>美团模式（门店配置默认）：跨订单/跨桌按<strong>同屏 + 菜名 + 规格 + 口味</strong>合并；
 * 堂食与打包默认内嵌同一行（{@code pack_inline_merge=1}）；全队列继承同一配置。</p>
 * <p>请求参数 {@code merge_rules} / {@code split_pack_takeout} 可临时覆盖门店配置。</p>
 */
public final class KdsBoardMergeRules {

    public static final String RULE_DISH = "dish";
    public static final String RULE_DINING = "dining";
    public static final String RULE_TAGS = "tags";

    private final boolean dish;
    private final boolean dining;
    private final boolean tags;
    private final boolean splitPackTakeout;
    private final boolean comboMerge;
    private final boolean crossOrder;
    private final boolean tagSplitOnMerge;

    private KdsBoardMergeRules(boolean dish, boolean dining, boolean tags, boolean splitPackTakeout,
                               boolean comboMerge, boolean crossOrder, boolean tagSplitOnMerge) {
        this.dish = dish;
        this.dining = dining;
        this.tags = tags;
        this.splitPackTakeout = splitPackTakeout;
        this.comboMerge = comboMerge;
        this.crossOrder = crossOrder;
        this.tagSplitOnMerge = tagSplitOnMerge;
    }

    public static KdsBoardMergeRules none() {
        return new KdsBoardMergeRules(false, false, false, false, true, false, false);
    }

    public static KdsBoardMergeRules dishOnly() {
        return new KdsBoardMergeRules(true, false, false, false, true, true, false);
    }

    public static KdsBoardMergeRules resolve(String raw, String normalizedQueue) {
        return resolve(raw, normalizedQueue, false, null);
    }

    public static KdsBoardMergeRules resolve(String raw, String normalizedQueue, boolean splitPackTakeout) {
        return resolve(raw, normalizedQueue, splitPackTakeout, null);
    }

    /**
     * 解析合并规则：未传 {@code merge_rules} 时从门店配置读取（美团默认全队列一致）。
     */
    public static KdsBoardMergeRules resolve(String raw, String normalizedQueue, boolean splitPackTakeoutFlag,
                                             KdsShopConfig shopCfg) {
        boolean splitExplicit = splitPackTakeoutFlag;
        if (StringUtils.hasText(raw)) {
            return resolveExplicit(raw, splitExplicit);
        }
        return fromShopConfig(shopCfg, splitExplicit);
    }

    private static KdsBoardMergeRules resolveExplicit(String raw, boolean splitPackTakeout) {
        String trimmed = raw.trim().toLowerCase(Locale.ROOT);
        if ("none".equals(trimmed) || "line".equals(trimmed) || "fifo".equals(trimmed)
                || "明细".equals(raw.trim()) || "不合并".equals(raw.trim())) {
            return none();
        }
        KdsBoardMergeRules parsed = parse(raw, splitPackTakeout);
        if (parsed.hasDish()) {
            boolean split = parsed.isSplitPackTakeout() || parsed.hasDining();
            return new KdsBoardMergeRules(true, parsed.hasDining(), parsed.hasTags(), split,
                    true, true, false);
        }
        return new KdsBoardMergeRules(false, parsed.hasDining(), parsed.hasTags(), parsed.isSplitPackTakeout(),
                true, false, parsed.hasTags());
    }

    private static KdsBoardMergeRules fromShopConfig(KdsShopConfig shopCfg, boolean splitPackTakeoutOverride) {
        boolean mergeDish = shopCfg == null || shopCfg.getMerge_same_dish() == null || shopCfg.getMerge_same_dish() != 0;
        boolean inlinePack = shopCfg == null || shopCfg.getPack_inline_merge() == null || shopCfg.getPack_inline_merge() != 0;
        boolean comboMerge = shopCfg == null || shopCfg.getCombo_merge() == null || shopCfg.getCombo_merge() != 0;
        boolean splitPack = splitPackTakeoutOverride || !inlinePack;
        if (!mergeDish) {
            return new KdsBoardMergeRules(false, false, false, splitPack, comboMerge, false, false);
        }
        return new KdsBoardMergeRules(true, false, false, splitPack, comboMerge, true, false);
    }

    public static KdsBoardMergeRules parse(String raw) {
        return parse(raw, false);
    }

    public static KdsBoardMergeRules parse(String raw, boolean splitPackTakeout) {
        if (!StringUtils.hasText(raw)) {
            return new KdsBoardMergeRules(false, false, false, splitPackTakeout, true, false, false);
        }
        boolean dish = false;
        boolean dining = false;
        boolean tags = false;
        for (String part : raw.split("[,;\\s]+")) {
            if (!StringUtils.hasText(part)) {
                continue;
            }
            String p = part.trim().toLowerCase(Locale.ROOT);
            if ("1".equals(p) || RULE_DISH.equals(p) || "菜品".equals(part.trim()) || "按菜品".equals(part.trim())) {
                dish = true;
            } else if ("2".equals(p) || RULE_DINING.equals(p) || "用餐".equals(part.trim()) || "就餐".equals(part.trim())) {
                dining = true;
            } else if ("3".equals(p) || RULE_TAGS.equals(p) || "标签".equals(part.trim())) {
                tags = true;
            }
        }
        return new KdsBoardMergeRules(dish, dining, tags, splitPackTakeout, true, dish, dish && !tags);
    }

    public static boolean parseSplitPackTakeoutFlag(String raw) {
        if (!StringUtils.hasText(raw)) {
            return false;
        }
        String p = raw.trim().toLowerCase(Locale.ROOT);
        return "1".equals(p) || "true".equals(p) || "on".equals(p) || "yes".equals(p)
                || "开".equals(raw.trim()) || "开启".equals(raw.trim());
    }

    public boolean hasDish() {
        return dish;
    }

    public boolean hasDining() {
        return dining;
    }

    public boolean hasTags() {
        return tags;
    }

    public boolean isSplitPackTakeout() {
        return splitPackTakeout;
    }

    public boolean isComboMerge() {
        return comboMerge;
    }

    public boolean isCrossOrder() {
        return crossOrder;
    }

    public boolean isTagSplitOnMerge() {
        return tagSplitOnMerge;
    }

    public boolean isDefaultFifoPerLine() {
        return !dish && !dining && !tags;
    }

    public List<String> toList() {
        List<String> out = new ArrayList<>();
        if (dish) {
            out.add(RULE_DISH);
        }
        if (dining) {
            out.add(RULE_DINING);
        }
        if (tags) {
            out.add(RULE_TAGS);
        }
        return out;
    }

    public static List<String> allRuleNames() {
        return Collections.unmodifiableList(java.util.Arrays.asList(RULE_DISH, RULE_DINING, RULE_TAGS));
    }
}
