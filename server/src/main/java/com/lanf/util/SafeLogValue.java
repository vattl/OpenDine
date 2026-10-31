package com.lanf.util;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * Produces a bounded diagnostic for untrusted or secret-bearing values without retaining their text in logs.
 */
public final class SafeLogValue {

    private static final int DIGEST_INPUT_MAX_CHARS = 4096;
    private static final int DIGEST_HEX_CHARS = 16;

    private SafeLogValue() {
    }

    public static String summarize(String value) {
        if (value == null) {
            return "absent";
        }
        int length = value.length();
        int digestChars = Math.min(length, DIGEST_INPUT_MAX_CHARS);
        String digestInput = value.substring(0, digestChars);
        return "chars=" + length
                + ",digestChars=" + digestChars
                + ",sha256=" + sha256Prefix(digestInput);
    }

    private static String sha256Prefix(String value) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(DIGEST_HEX_CHARS);
            for (int i = 0; i < bytes.length && hex.length() < DIGEST_HEX_CHARS; i++) {
                String pair = Integer.toHexString(bytes[i] & 0xff);
                if (pair.length() == 1) {
                    hex.append('0');
                }
                hex.append(pair);
            }
            return hex.substring(0, Math.min(hex.length(), DIGEST_HEX_CHARS));
        } catch (NoSuchAlgorithmException e) {
            return "unavailable";
        }
    }
}
