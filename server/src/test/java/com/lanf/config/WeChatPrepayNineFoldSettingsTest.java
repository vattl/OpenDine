package com.lanf.config;

import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WeChatPrepayNineFoldSettingsTest {

    @Test
    void canonicalDiningTypes() {
        assertEquals("堂食", WeChatPrepayNineFoldSettings.canonicalDiningType("dine_in"));
        assertEquals("打包", WeChatPrepayNineFoldSettings.canonicalDiningType("take_out"));
        assertEquals("外卖", WeChatPrepayNineFoldSettings.canonicalDiningType("waimai"));
    }

    @Test
    void eligibleDiningTypesFromDbJson() {
        WeChatPrepayNineFoldSettings s = new WeChatPrepayNineFoldSettings();
        s.applyFromKeyValue("wechat.prepay.ninefold.eligibleDiningTypes", "[\"堂食\",\"打包\"]");
        assertTrue(s.isEligibleDiningType("堂食"));
        assertTrue(s.isEligibleDiningType("打包"));
        assertFalse(s.isEligibleDiningType("外卖"));
    }

    @Test
    void qualifiesRequiresAllConditions() {
        WeChatPrepayNineFoldSettings s = new WeChatPrepayNineFoldSettings();
        s.setEnabled(true);
        s.setPayRate(0.9);
        s.setMinBaseYuan(60d);
        s.setEligibleDiningTypes(Collections.singletonList("堂食"));
        s.setWindowStart(java.time.LocalTime.MIDNIGHT);
        s.setWindowEnd(java.time.LocalTime.of(23, 59, 59));

        assertTrue(s.qualifiesForNineFold(false, new Date(), 100d, "堂食"));
        assertFalse(s.qualifiesForNineFold(false, new Date(), 100d, "打包"));
        assertFalse(s.qualifiesForNineFold(true, new Date(), 100d, "堂食"));
        assertFalse(s.qualifiesForNineFold(false, new Date(), 10d, "堂食"));
        s.setEnabled(false);
        assertFalse(s.qualifiesForNineFold(false, new Date(), 100d, "堂食"));
    }

    @Test
    void serializeEligibleTypes() {
        assertEquals("[\"堂食\",\"打包\"]",
                WeChatPrepayNineFoldSettings.serializeEligibleDiningTypes(Arrays.asList("堂食", "打包")));
    }
}
