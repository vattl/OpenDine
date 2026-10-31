package com.lanf.access.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ApprovalTokenEnvelopeCipherTest {

    @Test
    void roundTripUsesRandomizedAuthenticatedEnvelope() {
        ApprovalTokenEnvelopeCipher cipher = new ApprovalTokenEnvelopeCipher("unit-test-approval-envelope-key-32-bytes");

        String first = cipher.encrypt("QAP-1", "single-use-token");
        String second = cipher.encrypt("QAP-1", "single-use-token");

        assertTrue(first.startsWith("aet:v1:"));
        assertNotEquals("single-use-token", first);
        assertNotEquals(first, second, "每次加密必须使用随机 IV");
        assertEquals("single-use-token", cipher.decrypt("QAP-1", first));
        assertEquals("single-use-token", cipher.decrypt("QAP-1", second));
    }

    @Test
    void wrongApprovalCodeWrongKeyAndTamperingFailClosed() {
        ApprovalTokenEnvelopeCipher first = new ApprovalTokenEnvelopeCipher("unit-test-approval-envelope-key-A");
        ApprovalTokenEnvelopeCipher other = new ApprovalTokenEnvelopeCipher("unit-test-approval-envelope-key-B");
        String envelope = first.encrypt("QAP-1", "single-use-token");

        assertThrows(IllegalStateException.class, () -> first.decrypt("QAP-2", envelope));
        assertThrows(IllegalStateException.class, () -> other.decrypt("QAP-1", envelope));

        char last = envelope.charAt(envelope.length() - 1);
        String tampered = envelope.substring(0, envelope.length() - 1) + (last == 'A' ? 'B' : 'A');
        assertThrows(IllegalStateException.class, () -> first.decrypt("QAP-1", tampered));
    }

    @Test
    void missingKeyAndLegacyPlaintextAreRejected() {
        ApprovalTokenEnvelopeCipher unconfigured = new ApprovalTokenEnvelopeCipher("");
        assertThrows(IllegalStateException.class, () -> unconfigured.encrypt("QAP-1", "token"));
        assertThrows(IllegalStateException.class, () -> unconfigured.decrypt("QAP-1", "aet:v1:AAAA"));

        ApprovalTokenEnvelopeCipher configured = new ApprovalTokenEnvelopeCipher("unit-test-approval-envelope-key-32-bytes");
        assertThrows(IllegalStateException.class, () -> configured.decrypt("QAP-1", "legacy-raw-token"));
    }
}
