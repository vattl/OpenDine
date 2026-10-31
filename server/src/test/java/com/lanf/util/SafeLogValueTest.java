package com.lanf.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SafeLogValueTest {

    @Test
    void summarizesSensitiveValueWithoutRetainingIt() {
        String summary = SafeLogValue.summarize("Bearer secret-token-value");

        assertTrue(summary.startsWith("chars=25,digestChars=25,sha256="));
        assertFalse(summary.contains("secret-token-value"));
        assertEquals(summary, SafeLogValue.summarize("Bearer secret-token-value"));
    }

    @Test
    void boundsDigestInputForLargeBodies() {
        String body = repeat('x', 5000);

        String summary = SafeLogValue.summarize(body);

        assertTrue(summary.startsWith("chars=5000,digestChars=4096,sha256="));
        assertFalse(summary.contains(body));
    }

    private static String repeat(char value, int count) {
        StringBuilder result = new StringBuilder(count);
        for (int i = 0; i < count; i++) {
            result.append(value);
        }
        return result.toString();
    }
}
