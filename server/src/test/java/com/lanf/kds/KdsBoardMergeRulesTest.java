package com.lanf.kds;

import com.lanf.kds.entity.KdsShopConfig;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsBoardMergeRulesTest {

    @Test
    void shopDefault_isMeituanCrossOrderMerge() {
        KdsBoardMergeRules rules = KdsBoardMergeRules.resolve(null, KdsWorkflowQueue.PENDING_PREP, false, new KdsShopConfig());
        assertTrue(rules.hasDish());
        assertTrue(rules.isCrossOrder());
        assertFalse(rules.isSplitPackTakeout());
        assertTrue(rules.isComboMerge());
        assertFalse(rules.isTagSplitOnMerge());
    }

    @Test
    void shopMergeOff_isPerLine() {
        KdsShopConfig cfg = new KdsShopConfig();
        cfg.setMerge_same_dish(0);
        KdsBoardMergeRules rules = KdsBoardMergeRules.resolve(null, KdsWorkflowQueue.PENDING_COOK, false, cfg);
        assertFalse(rules.hasDish());
        assertFalse(rules.isCrossOrder());
    }

    @Test
    void shopPackSplit_enablesChannelSplit() {
        KdsShopConfig cfg = new KdsShopConfig();
        cfg.setPack_inline_merge(0);
        KdsBoardMergeRules rules = KdsBoardMergeRules.resolve(null, KdsWorkflowQueue.READY_SERVE, false, cfg);
        assertTrue(rules.isSplitPackTakeout());
    }

    @Test
    void explicitNone_overridesShop() {
        KdsShopConfig cfg = new KdsShopConfig();
        cfg.setMerge_same_dish(1);
        KdsBoardMergeRules rules = KdsBoardMergeRules.resolve("none", KdsWorkflowQueue.PENDING_PREP, false, cfg);
        assertFalse(rules.hasDish());
    }
}
