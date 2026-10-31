package com.lanf.payment.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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
 * 支付配置密钥加解密。主密钥来自环境变量 {@code PAYMENT_CONFIG_MASTER_KEY}；
 * 生产默认 fail closed；仅显式开启 debug 开关时才允许生成 {@code plain:} 兼容值。
 */
@Component
public class PaymentCredentialCipher {

    private static final Logger log = LoggerFactory.getLogger(PaymentCredentialCipher.class);
    private static final String PLAIN_PREFIX = "plain:";
    private static final String ENC_PREFIX = "enc:";
    private static final int GCM_TAG_BITS = 128;
    private static final int GCM_IV_BYTES = 12;

    private final byte[] aesKey;
    private final boolean allowPlaintext;

    @org.springframework.beans.factory.annotation.Autowired
    public PaymentCredentialCipher(@Value("${payment.config-master-key:}") String masterKeyProp,
                                   @Value("${payment.allow-plaintext-credentials:false}") boolean allowPlaintext) {
        this.allowPlaintext = allowPlaintext;
        String mk = masterKeyProp;
        if (!StringUtils.hasText(mk)) {
            mk = System.getenv("PAYMENT_CONFIG_MASTER_KEY");
        }
        if (StringUtils.hasText(mk)) {
            try {
                this.aesKey = MessageDigest.getInstance("SHA-256")
                        .digest(mk.trim().getBytes(StandardCharsets.UTF_8));
            } catch (Exception e) {
                throw new IllegalStateException("初始化支付配置主密钥失败", e);
            }
        } else {
            this.aesKey = null;
            log.warn("未配置 payment.config-master-key / PAYMENT_CONFIG_MASTER_KEY，支付商户密钥写入已禁用");
        }
    }

    /** 测试及旧调用兼容；不允许明文写入。 */
    public PaymentCredentialCipher(String masterKeyProp) {
        this(masterKeyProp, false);
    }

    public String encrypt(String plain) {
        if (!StringUtils.hasText(plain)) {
            return plain;
        }
        if (aesKey == null) {
            if (allowPlaintext) {
                log.warn("仅限调试：正在以 plain: 格式保存支付商户凭据");
                return PLAIN_PREFIX + plain;
            }
            throw new IllegalStateException("未配置支付配置主密钥，禁止保存商户密钥");
        }
        try {
            byte[] iv = new byte[GCM_IV_BYTES];
            new SecureRandom().nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(aesKey, "AES"), new GCMParameterSpec(GCM_TAG_BITS, iv));
            byte[] ct = cipher.doFinal(plain.getBytes(StandardCharsets.UTF_8));
            ByteBuffer buf = ByteBuffer.allocate(iv.length + ct.length);
            buf.put(iv);
            buf.put(ct);
            return ENC_PREFIX + Base64.getEncoder().encodeToString(buf.array());
        } catch (Exception e) {
            throw new IllegalStateException("加密支付配置失败", e);
        }
    }

    public String decrypt(String stored) {
        if (!StringUtils.hasText(stored)) {
            return stored;
        }
        if (stored.startsWith(PLAIN_PREFIX)) {
            return stored.substring(PLAIN_PREFIX.length());
        }
        if (!stored.startsWith(ENC_PREFIX)) {
            return stored;
        }
        if (aesKey == null) {
            log.warn("存在 enc: 密文但未配置主密钥，无法解密");
            return "";
        }
        try {
            byte[] raw = Base64.getDecoder().decode(stored.substring(ENC_PREFIX.length()));
            ByteBuffer buf = ByteBuffer.wrap(raw);
            byte[] iv = new byte[GCM_IV_BYTES];
            buf.get(iv);
            byte[] ct = new byte[buf.remaining()];
            buf.get(ct);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(aesKey, "AES"), new GCMParameterSpec(GCM_TAG_BITS, iv));
            return new String(cipher.doFinal(ct), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("解密支付配置失败", e);
        }
    }

    public static String maskSecret(String value) {
        if (!StringUtils.hasText(value)) {
            return "";
        }
        String t = value.trim();
        if (t.length() <= 4) {
            return "****";
        }
        return "******" + t.substring(t.length() - 4);
    }

    public static boolean isMaskPlaceholder(String input) {
        return input != null && input.contains("******");
    }
}
