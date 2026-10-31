package com.lanf.access.security;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * 二维码审批令牌的短期持久化信封。
 *
 * <p>信封只用于在多个应用实例之间交付已批准的一次性令牌；令牌检索仍以
 * {@code token_hash} 为准。审批号作为 GCM AAD，防止密文被移动到另一审批记录。</p>
 */
@Component
public class ApprovalTokenEnvelopeCipher {

    private static final String PREFIX = "aet:v1:";
    private static final int GCM_TAG_BITS = 128;
    private static final int GCM_IV_BYTES = 12;
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private final byte[] aesKey;

    @Autowired
    public ApprovalTokenEnvelopeCipher(@Value("${approval.token-envelope-key:}") String masterKey) {
        if (!StringUtils.hasText(masterKey)
                || masterKey.trim().getBytes(StandardCharsets.UTF_8).length < 32) {
            this.aesKey = null;
            return;
        }
        try {
            this.aesKey = MessageDigest.getInstance("SHA-256")
                    .digest(masterKey.trim().getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException("初始化审批令牌信封密钥失败", e);
        }
    }

    public boolean isConfigured() {
        return aesKey != null;
    }

    public String encrypt(String approvalCode, String rawToken) {
        requireConfigured();
        requireText(approvalCode, "审批号不能为空");
        requireText(rawToken, "审批令牌不能为空");
        try {
            byte[] iv = new byte[GCM_IV_BYTES];
            SECURE_RANDOM.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(aesKey, "AES"),
                    new GCMParameterSpec(GCM_TAG_BITS, iv));
            cipher.updateAAD(approvalCode.trim().getBytes(StandardCharsets.UTF_8));
            byte[] ciphertext = cipher.doFinal(rawToken.getBytes(StandardCharsets.UTF_8));
            return PREFIX + Base64.getEncoder().encodeToString(
                    ByteBuffer.allocate(iv.length + ciphertext.length)
                            .put(iv)
                            .put(ciphertext)
                            .array());
        } catch (Exception e) {
            throw new IllegalStateException("加密审批令牌信封失败", e);
        }
    }

    public String decrypt(String approvalCode, String envelope) {
        requireConfigured();
        requireText(approvalCode, "审批号不能为空");
        if (!StringUtils.hasText(envelope) || !envelope.startsWith(PREFIX)) {
            throw new IllegalStateException("审批令牌信封格式无效");
        }
        try {
            byte[] packed = Base64.getDecoder().decode(envelope.substring(PREFIX.length()));
            if (packed.length <= GCM_IV_BYTES + (GCM_TAG_BITS / 8)) {
                throw new IllegalStateException("审批令牌信封长度无效");
            }
            ByteBuffer buffer = ByteBuffer.wrap(packed);
            byte[] iv = new byte[GCM_IV_BYTES];
            buffer.get(iv);
            byte[] ciphertext = new byte[buffer.remaining()];
            buffer.get(ciphertext);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(aesKey, "AES"),
                    new GCMParameterSpec(GCM_TAG_BITS, iv));
            cipher.updateAAD(approvalCode.trim().getBytes(StandardCharsets.UTF_8));
            return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
        } catch (IllegalStateException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("审批令牌信封认证失败", e);
        }
    }

    private void requireConfigured() {
        if (!isConfigured()) {
            throw new IllegalStateException("未配置至少 32 字节的审批令牌信封密钥");
        }
    }

    private void requireText(String value, String message) {
        if (!StringUtils.hasText(value)) {
            throw new IllegalStateException(message);
        }
    }
}
