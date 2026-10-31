package com.lanf.payment.support;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Calendar;

/**
 * 支付相关商户单号生成（与 {@code OrderController} 原逻辑一致）。
 */
public final class PaymentOrderNoUtil {

    private PaymentOrderNoUtil() {
    }

    public static String buildOutTradeNo(String orderNo) {
        if (orderNo == null) {
            orderNo = "";
        }
        long ts = System.currentTimeMillis() % 10000000000L;
        String suffix = "_" + ts;
        if (orderNo.length() + suffix.length() > 32) {
            orderNo = orderNo.substring(0, 32 - suffix.length());
        }
        return orderNo + suffix;
    }

    public static String generateOrderNo() {
        return PaymentMerchantNoUtil.PREFIX_DINING + timestampSuffix();
    }

    public static String generateRechargeOrderNo() {
        return PaymentMerchantNoUtil.PREFIX_WX_RECHARGE + timestampSuffix();
    }

    /** 商户退款单号 out_refund_no（同商户唯一，长度不超过 64）。 */
    public static String buildOutRefundNo(String orderNo) {
        if (orderNo == null || orderNo.isEmpty()) {
            orderNo = PaymentMerchantNoUtil.PREFIX_DINING;
        }
        String ts = String.valueOf(System.currentTimeMillis());
        String raw = "RF_" + orderNo + "_" + ts;
        return raw.length() > 64 ? raw.substring(0, 64) : raw;
    }

    /**
     * Stable refund number for an idempotent refund attempt. A retry before the
     * success notification reuses the same merchant refund number.
     */
    public static String buildOutRefundNo(
            String orderNo, int alreadyRefundedFen, int refundFen) {
        String normalized = orderNo == null ? "" : orderNo.replaceAll("[^A-Za-z0-9_-]", "");
        if (normalized.isEmpty()) {
            normalized = PaymentMerchantNoUtil.PREFIX_DINING;
        }
        String suffix = "_" + Math.max(0, alreadyRefundedFen) + "_" + Math.max(0, refundFen);
        int maxOrderLength = Math.max(1, 64 - "RF_".length() - suffix.length());
        if (normalized.length() > maxOrderLength) {
            normalized = normalized.substring(0, maxOrderLength);
        }
        return "RF_" + normalized + suffix;
    }

    /**
     * Stable refund number derived from the caller's persistent idempotency key.
     */
    public static String buildOutRefundNo(String orderNo, String idempotencyKey) {
        String normalized = orderNo == null ? "" : orderNo.replaceAll("[^A-Za-z0-9_-]", "");
        if (normalized.isEmpty()) {
            normalized = PaymentMerchantNoUtil.PREFIX_DINING;
        }
        String suffix = "_" + sha256Hex(idempotencyKey == null ? "" : idempotencyKey).substring(0, 20);
        int maxOrderLength = Math.max(1, 64 - "RF_".length() - suffix.length());
        if (normalized.length() > maxOrderLength) {
            normalized = normalized.substring(0, maxOrderLength);
        }
        return "RF_" + normalized + suffix;
    }

    private static String sha256Hex(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder(digest.length * 2);
            for (byte b : digest) {
                result.append(String.format("%02x", b & 0xff));
            }
            return result.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    private static String timestampSuffix() {
        Calendar cal = Calendar.getInstance();
        String y = String.valueOf(cal.get(Calendar.YEAR));
        String M = padZero(cal.get(Calendar.MONTH) + 1);
        String d = padZero(cal.get(Calendar.DAY_OF_MONTH));
        String H = padZero(cal.get(Calendar.HOUR_OF_DAY));
        String m = padZero(cal.get(Calendar.MINUTE));
        String s = padZero(cal.get(Calendar.SECOND));
        int rand = (int) (Math.random() * 1000);
        return y + M + d + H + m + s + rand;
    }

    private static String padZero(int n) {
        return n < 10 ? "0" + n : String.valueOf(n);
    }
}
