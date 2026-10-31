package com.lanf.payment.support;

import org.springframework.util.StringUtils;

/**
 * 支付商户配置字段校验（避免 DB 截断与误填 PEM）。
 */
public final class PaymentMerchantFieldValidator {

    public static final int MAX_PLATFORM_PUB_KEY_ID_LEN = 128;
    public static final int MAX_SERIAL_NO_LEN = 64;
    public static final int MAX_PRIVATE_KEY_REF_LEN = 512;
    public static final int MAX_PLATFORM_PUB_KEY_REF_LEN = 512;

    private PaymentMerchantFieldValidator() {
    }

    /**
     * 微信 {@code Wechatpay-Serial} 对应的平台公钥 ID（如 PUB_KEY_ID_xxx），非 PEM 内容。
     */
    public static String normalizePlatformPubKeyId(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String v = raw.trim();
        if (v.contains("\n") || v.contains("\r")) {
            v = v.replace("\r", "").replace("\n", "").trim();
        }
        rejectPemContent(v, "platformPubKeyId");
        if (v.length() > MAX_PLATFORM_PUB_KEY_ID_LEN) {
            throw new IllegalArgumentException(
                    "platformPubKeyId 过长（最多 " + MAX_PLATFORM_PUB_KEY_ID_LEN + " 字符）。"
                            + "请填写微信支付平台公钥 ID（如 PUB_KEY_ID_0117258570172025082800112359000000）；"
                            + "公钥 PEM 请写入 platformPubKeyRef 字段");
        }
        return v;
    }

    /**
     * 平台公钥 PEM 或 classpath: 路径（验签用）。
     */
    public static String normalizePlatformPubKeyRef(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String v = raw.trim();
        if (v.startsWith("classpath:")) {
            if (v.length() > MAX_PLATFORM_PUB_KEY_REF_LEN) {
                throw new IllegalArgumentException(
                        "platformPubKeyRef 路径过长（最多 " + MAX_PLATFORM_PUB_KEY_REF_LEN + " 字符）");
            }
            return v;
        }
        if (v.length() > MAX_PLATFORM_PUB_KEY_REF_LEN) {
            throw new IllegalArgumentException(
                    "platformPubKeyRef 过长（最多 " + MAX_PLATFORM_PUB_KEY_REF_LEN + " 字符）。"
                            + "可填 classpath:pub_key.pem 或内联 -----BEGIN PUBLIC KEY----- PEM");
        }
        return v;
    }

    public static String normalizeSerialNo(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String v = raw.trim();
        rejectPemContent(v, "serialNo");
        if (v.length() > MAX_SERIAL_NO_LEN) {
            throw new IllegalArgumentException(
                    "serialNo 过长（最多 " + MAX_SERIAL_NO_LEN + " 字符），请填写商户 API 证书序列号（40 位十六进制）");
        }
        return v;
    }

    public static String normalizePrivateKeyRef(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String v = raw.trim();
        if (v.contains("-----BEGIN") || v.contains("-----END")) {
            throw new IllegalArgumentException(
                    "privateKeyRef 不能直接填写 PEM 私钥内容。请先调用私钥上传接口，"
                            + "由后端保存服务器文件后再把返回的 privateKeyRef 路径写入数据库");
        }
        if (v.startsWith("classpath:")) {
            if (v.length() > MAX_PRIVATE_KEY_REF_LEN) {
                throw new IllegalArgumentException("privateKeyRef 路径过长（最多 " + MAX_PRIVATE_KEY_REF_LEN + " 字符）");
            }
            return v;
        }
        if (v.length() > MAX_PRIVATE_KEY_REF_LEN) {
            throw new IllegalArgumentException(
                    "privateKeyRef 过长（最多 " + MAX_PRIVATE_KEY_REF_LEN + " 字符）。"
                            + "完整 PEM 私钥请调用私钥上传接口保存到服务器，数据库仅记录返回路径；"
                            + "也可使用 classpath:apiclient_key.pem 等形式引用已部署文件");
        }
        return v;
    }

    private static void rejectPemContent(String v, String field) {
        if (v.contains("BEGIN") || v.contains("-----END")) {
            throw new IllegalArgumentException(field + " 不能填写 PEM 证书/公钥内容，"
                    + "platformPubKeyId 请填 PUB_KEY_ID_xxx；公钥 PEM 请填 platformPubKeyRef");
        }
    }
}
