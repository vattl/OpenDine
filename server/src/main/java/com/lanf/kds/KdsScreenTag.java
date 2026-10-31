package com.lanf.kds;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * PRD 五屏 screen_tag 常量。
 */
public final class KdsScreenTag {

    public static final String SKEWER_AGGREGATE = "skewer_aggregate";
    public static final String MEAT_GRILL = "meat_grill";
    public static final String VEG_GRILL = "veg_grill";
    public static final String SEAFOOD_SPECIAL = "seafood_special";
    public static final String EXPEDITION = "expedition";
    /** 收银/老板总览屏：跨烤制岗汇总，只读看板 */
    public static final String BOSS_OVERVIEW = "boss_overview";
    /** 统一工作流看板：按 prep/cook/serve 多流程展示 */
    public static final String WORKFLOW_BOARD = "workflow_board";

    private static final Set<String> ALL = Collections.unmodifiableSet(
            Arrays.stream(new String[]{
                    SKEWER_AGGREGATE, MEAT_GRILL, VEG_GRILL, SEAFOOD_SPECIAL, EXPEDITION, BOSS_OVERVIEW, WORKFLOW_BOARD
            }).collect(Collectors.toSet()));

    /** 烤制生产岗（总览屏汇总范围，不含抓串/出餐） */
    public static final List<String> PRODUCTION_GRILL_TAGS = Collections.unmodifiableList(
            Arrays.asList(MEAT_GRILL, VEG_GRILL, SEAFOOD_SPECIAL));

    private static final List<FiveScreenSeed> FIVE_SCREENS = Arrays.asList(
            new FiveScreenSeed("SKEWER", SKEWER_AGGREGATE, "抓串汇总屏", 1),
            new FiveScreenSeed("MEAT", MEAT_GRILL, "荤菜烤制屏", 2),
            new FiveScreenSeed("VEG", VEG_GRILL, "素菜烤制屏", 3),
            new FiveScreenSeed("SEA", SEAFOOD_SPECIAL, "海鲜特色屏", 4),
            new FiveScreenSeed("EXP", EXPEDITION, "总出餐核对屏", 5),
            new FiveScreenSeed("BOSS", BOSS_OVERVIEW, "收银总览屏", 6)
    );

    private KdsScreenTag() {
    }

    public static boolean isValid(String tag) {
        return tag != null && ALL.contains(tag.trim());
    }

    public static List<FiveScreenSeed> fiveScreenSeeds() {
        return FIVE_SCREENS;
    }

    /** 多屏 WS 广播用 */
    public static List<String> allBroadcastTags() {
        return Arrays.asList(
                SKEWER_AGGREGATE, MEAT_GRILL, VEG_GRILL, SEAFOOD_SPECIAL, EXPEDITION, BOSS_OVERVIEW, WORKFLOW_BOARD);
    }

    public static Map<String, String> fiveScreenTagToName() {
        Map<String, String> m = new LinkedHashMap<>();
        for (FiveScreenSeed s : FIVE_SCREENS) {
            m.put(s.screenTag, s.name);
        }
        return m;
    }

    public static final class FiveScreenSeed {
        public final String code;
        public final String screenTag;
        public final String name;
        public final int sort;

        FiveScreenSeed(String code, String screenTag, String name, int sort) {
            this.code = code;
            this.screenTag = screenTag;
            this.name = name;
            this.sort = sort;
        }
    }
}
