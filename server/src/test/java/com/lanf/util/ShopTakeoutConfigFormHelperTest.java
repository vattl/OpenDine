package com.lanf.util;

import com.lanf.entity.ShopTakeoutConfig;
import org.junit.jupiter.api.Test;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ShopTakeoutConfigFormHelperTest {

    @Test
    void applyMap_parsesEnabledToggle() {
        ShopTakeoutConfig cfg = ShopTakeoutConfigFormHelper.newDefault(1);
        ShopTakeoutConfigFormHelper.applyMap(cfg, Collections.singletonMap("enabled", 1));
        assertEquals(1, cfg.getEnabled());
    }
}
