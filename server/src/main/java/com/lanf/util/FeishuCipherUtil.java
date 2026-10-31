package com.lanf.util;

import lombok.extern.slf4j.Slf4j;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

/**
 * 飞书事件加解密工具类（遵循飞书开放平台 AES-256-CBC 规范）
 */
@Slf4j
public class FeishuCipherUtil {

    private static final String ALGORITHM = "AES";
    private static final String CIPHER_ALGORITHM = "AES/CBC/PKCS5Padding";

    /**
     * 对飞书推送的加密串进行解密
     *
     * @param encryptBase64 飞书请求中的 encrypt 密文字符串（Base64编码）
     * @param encryptKey    开发者后台配置的 Encrypt Key
     * @return 解密后的 JSON 明文字符串
     */
    public static String decrypt(String encryptBase64, String encryptKey) {
        if (encryptBase64 == null || encryptBase64.trim().isEmpty()) {
            throw new IllegalArgumentException("Encrypt text cannot be empty");
        }
        if (encryptKey == null || encryptKey.trim().isEmpty()) {
            throw new IllegalArgumentException("Encrypt key cannot be empty");
        }

        try {
            byte[] decodeBytes = Base64.getDecoder().decode(encryptBase64);
            if (decodeBytes.length <= 16) {
                throw new IllegalArgumentException("Ciphertext length is too short");
            }

            // 1. 密钥通过 SHA-256 生成 32 字节 Key
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] keyBytes = digest.digest(encryptKey.getBytes(StandardCharsets.UTF_8));
            SecretKeySpec secretKeySpec = new SecretKeySpec(keyBytes, ALGORITHM);

            // 2. 前 16 字节为 IV
            byte[] ivBytes = Arrays.copyOfRange(decodeBytes, 0, 16);
            IvParameterSpec ivParameterSpec = new IvParameterSpec(ivBytes);

            // 3. 16 字节之后为密文主体
            byte[] cipherBytes = Arrays.copyOfRange(decodeBytes, 16, decodeBytes.length);

            Cipher cipher = Cipher.getInstance(CIPHER_ALGORITHM);
            cipher.init(Cipher.DECRYPT_MODE, secretKeySpec, ivParameterSpec);

            byte[] plainBytes = cipher.doFinal(cipherBytes);
            return new String(plainBytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            log.error("Failed to decrypt Feishu event payload", e);
            throw new RuntimeException("飞书消息解密失败: " + e.getMessage(), e);
        }
    }

    /**
     * 对明文字符串进行飞书规范的 AES 加密（供单测与端到端验证）
     *
     * @param plainText  明文字符串
     * @param encryptKey 开发者后台配置的 Encrypt Key
     * @return Base64 编码的密文字符串（包含前置 16 字节 IV）
     */
    public static String encrypt(String plainText, String encryptKey) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] keyBytes = digest.digest(encryptKey.getBytes(StandardCharsets.UTF_8));
            SecretKeySpec secretKeySpec = new SecretKeySpec(keyBytes, ALGORITHM);

            byte[] ivBytes = new byte[16];
            new SecureRandom().nextBytes(ivBytes);
            IvParameterSpec ivParameterSpec = new IvParameterSpec(ivBytes);

            Cipher cipher = Cipher.getInstance(CIPHER_ALGORITHM);
            cipher.init(Cipher.ENCRYPT_MODE, secretKeySpec, ivParameterSpec);

            byte[] cipherBytes = cipher.doFinal(plainText.getBytes(StandardCharsets.UTF_8));

            byte[] combined = new byte[ivBytes.length + cipherBytes.length];
            System.arraycopy(ivBytes, 0, combined, 0, ivBytes.length);
            System.arraycopy(cipherBytes, 0, combined, ivBytes.length, cipherBytes.length);

            return Base64.getEncoder().encodeToString(combined);
        } catch (Exception e) {
            throw new RuntimeException("飞书消息加密失败: " + e.getMessage(), e);
        }
    }
}
