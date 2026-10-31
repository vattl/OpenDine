package com.lanf.adminlog.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LogMaskUtilSensitiveFieldsTest {

    @Test
    void mask_shouldRedactNestedAuthorizationPassword() {
        String masked = LogMaskUtil.mask(
                "{\"authorization\":{\"account\":\"M1001\",\"password\":\"p\\\"ass\"}}");

        assertFalse(masked.contains("p\\\"ass"));
        assertTrue(masked.contains("\"password\":\"****\""));
        assertTrue(masked.contains("M1001"));
    }
}
