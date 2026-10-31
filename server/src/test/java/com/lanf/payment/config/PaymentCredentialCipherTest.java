package com.lanf.payment.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class PaymentCredentialCipherTest {
    @Test
    void rejectsNewSecretWithoutMasterKeyByDefault() {
        PaymentCredentialCipher cipher = new PaymentCredentialCipher("", false);
        assertThrows(IllegalStateException.class, () -> cipher.encrypt("12345678901234567890123456789012"));
    }

    @Test
    void debugFlagExplicitlyAllowsLegacyPlaintext() {
        PaymentCredentialCipher cipher = new PaymentCredentialCipher("", true);
        assertEquals("plain:secret", cipher.encrypt("secret"));
    }

    @Test
    void encryptedValueRoundTripsWithMasterKey() {
        PaymentCredentialCipher cipher = new PaymentCredentialCipher("unit-test-master-key", false);
        String encrypted = cipher.encrypt("secret");
        assertEquals("secret", cipher.decrypt(encrypted));
    }
}
