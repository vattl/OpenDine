package com.lanf.util;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * 管理员密码兼容工具：
 * - 新写入统一使用 BCrypt
 * - 登录时兼容历史明文，成功后可升级为 BCrypt
 */
public final class AdminPasswordUtil {

    private static final PasswordEncoder ENCODER = new BCryptPasswordEncoder();

    private AdminPasswordUtil() {
    }

    public static String encode(String rawPassword) {
        if (rawPassword == null) {
            return null;
        }
        return ENCODER.encode(rawPassword);
    }

    public static boolean matches(String rawPassword, String storedPassword) {
        if (rawPassword == null || storedPassword == null) {
            return false;
        }
        String raw = rawPassword.trim();
        String stored = storedPassword.trim();
        if (stored.isEmpty()) {
            return false;
        }
        if (isBcryptHash(stored)) {
            return ENCODER.matches(raw, stored);
        }
        return stored.equals(raw);
    }

    public static boolean needsUpgrade(String storedPassword) {
        if (storedPassword == null) {
            return true;
        }
        return !isBcryptHash(storedPassword.trim());
    }

    private static boolean isBcryptHash(String value) {
        return value.startsWith("$2a$") || value.startsWith("$2b$") || value.startsWith("$2y$");
    }
}
