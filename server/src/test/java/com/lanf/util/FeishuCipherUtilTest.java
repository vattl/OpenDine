package com.lanf.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class FeishuCipherUtilTest {

    @Test
    public void testEncryptAndDecrypt_success() {
        String encryptKey = "test_encrypt_key_1234567890abcdef";
        String plainText = "{\"event\":{\"message\":{\"text\":\"今天做小红书油边王种草\"}}}";

        String cipherText = FeishuCipherUtil.encrypt(plainText, encryptKey);
        assertNotNull(cipherText);
        assertNotEquals(plainText, cipherText);

        String decrypted = FeishuCipherUtil.decrypt(cipherText, encryptKey);
        assertEquals(plainText, decrypted);
    }

    @Test
    public void testDecrypt_withInvalidKey_throwsException() {
        String encryptKey = "correct_key_1234567890abcdef";
        String wrongKey = "wrong_key_1234567890abcdef";
        String plainText = "{\"type\":\"url_verification\"}";

        String cipherText = FeishuCipherUtil.encrypt(plainText, encryptKey);

        assertThrows(RuntimeException.class, () -> {
            FeishuCipherUtil.decrypt(cipherText, wrongKey);
        });
    }

    @Test
    public void testDecrypt_emptyInputs_throwsIllegalArgumentException() {
        assertThrows(IllegalArgumentException.class, () -> {
            FeishuCipherUtil.decrypt("", "key");
        });
        assertThrows(IllegalArgumentException.class, () -> {
            FeishuCipherUtil.decrypt("abc", "");
        });
    }
}
