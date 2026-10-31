package com.lanf.config;

import com.lanf.constant.ZsqSystemConfigKeys;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ZsqSystemSettingsTest {

    @Test
    void shopOverrideFallsBackToGlobal() {
        ZsqSystemSettings s = new ZsqSystemSettings(false, true);
        s.applyFromKeyValue(ZsqSystemSettings.GLOBAL_SHOP_ID, ZsqSystemConfigKeys.AUTO_API_ENABLED, "1");
        s.applyFromKeyValue(3, ZsqSystemConfigKeys.AUTO_API_ENABLED, "0");
        assertTrue(s.isAutoDispatchEnabled(null));
        assertFalse(s.isAutoDispatchEnabled(3));
        assertTrue(s.isAutoDispatchEnabled(99));
    }

    @Test
    void toPublicMapReflectsAutoDispatch() {
        ZsqSystemSettings s = new ZsqSystemSettings(false, true);
        s.setAutoDispatchEnabled(2, true);
        assertTrue((Boolean) s.toPublicMap(2).get("autoDispatchEnabled"));
        s.setAutoDispatchEnabled(2, false);
        assertFalse((Boolean) s.toPublicMap(2).get("autoDispatchEnabled"));
    }
}
