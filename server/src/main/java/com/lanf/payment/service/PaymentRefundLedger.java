package com.lanf.payment.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;


import java.util.List;
import java.util.Map;

/**
 * Durable idempotency ledger and per-order mutex for payment refunds.
 */
@Component
@org.springframework.context.annotation.DependsOn("paymentSchemaReadiness")
public class PaymentRefundLedger {

    private final JdbcTemplate jdbc;

    public PaymentRefundLedger(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }



    @Transactional(rollbackFor = Exception.class)
    public Entry reserve(
            int shopId,
            String orderNo,
            String idempotencyKey,
            String outRefundNo,
            int requestedFen) {
        return reserve(shopId, orderNo, idempotencyKey, outRefundNo, requestedFen,
                null, null, null, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public Entry reserve(
            int shopId,
            String orderNo,
            String idempotencyKey,
            String outRefundNo,
            int requestedFen,
            Long merchantConfigId,
            Integer merchantConfigVersion,
            String expectedTransactionId,
            String expectedMchId) {
        validate(shopId, orderNo, idempotencyKey, outRefundNo, requestedFen);
        jdbc.update("INSERT IGNORE INTO t_payment_refund_request "
                        + "(shop_id, order_no, idempotency_key, out_refund_no, requested_fen, "
                        + "merchant_config_id, merchant_config_version, expected_transaction_id, expected_mch_id) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                shopId, orderNo.trim(), idempotencyKey.trim(),
                outRefundNo.trim(), requestedFen, merchantConfigId, merchantConfigVersion,
                trimToNull(expectedTransactionId), trimToNull(expectedMchId));
        Entry entry = findByIdempotencyKeyForUpdate(shopId, idempotencyKey);
        if (entry == null
                || !orderNo.trim().equals(entry.orderNo)
                || !outRefundNo.trim().equals(entry.outRefundNo)
                || requestedFen != entry.requestedFen
                || !sameNullable(merchantConfigId, entry.merchantConfigId)
                || !sameNullable(merchantConfigVersion, entry.merchantConfigVersion)
                || !sameNullable(trimToNull(expectedTransactionId), entry.expectedTransactionId)
                || !sameNullable(trimToNull(expectedMchId), entry.expectedMchId)) {
            throw new IllegalStateException("退款幂等键已被其他退款请求占用");
        }
        if (entry.isSuccessful() || entry.isRejected()) {
            return entry;
        }
        if (!acquireOrderGuard(shopId, orderNo, idempotencyKey)) {
            jdbc.update("UPDATE t_payment_refund_request SET status = 'REJECTED' "
                            + "WHERE shop_id = ? AND idempotency_key = ? "
                            + "AND status <> 'SUCCESS'",
                    shopId, idempotencyKey.trim());
            return new Entry(entry.orderNo, entry.idempotencyKey,
                    entry.outRefundNo, entry.requestedFen,
                    entry.appliedFen, "REJECTED", entry.shopId,
                    entry.merchantConfigId, entry.merchantConfigVersion,
                    entry.expectedTransactionId, entry.expectedMchId);
        }
        if ("FAILED".equals(entry.status)) {
            jdbc.update("UPDATE t_payment_refund_request SET status = 'REQUESTED' "
                            + "WHERE shop_id = ? AND idempotency_key = ?",
                    shopId, idempotencyKey.trim());
            return new Entry(entry.orderNo, entry.idempotencyKey,
                    entry.outRefundNo, entry.requestedFen,
                    entry.appliedFen, "REQUESTED", entry.shopId,
                    entry.merchantConfigId, entry.merchantConfigVersion,
                    entry.expectedTransactionId, entry.expectedMchId);
        }
        return entry;
    }

    private boolean acquireOrderGuard(
            int shopId, String orderNo, String idempotencyKey) {
        jdbc.update("INSERT IGNORE INTO t_payment_refund_guard "
                        + "(shop_id, order_no, idempotency_key) VALUES (?, ?, ?)",
                shopId, orderNo.trim(), idempotencyKey.trim());
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT idempotency_key FROM t_payment_refund_guard "
                        + "WHERE shop_id = ? AND order_no = ? LIMIT 1 FOR UPDATE",
                shopId, orderNo.trim());
        return !rows.isEmpty()
                && idempotencyKey.trim().equals(
                String.valueOf(rows.get(0).get("idempotency_key")));
    }

    public Entry findByIdempotencyKeyForUpdate(
            int shopId, String idempotencyKey) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                selectColumns()
                        + "FROM t_payment_refund_request "
                        + "WHERE shop_id = ? AND idempotency_key = ? "
                        + "LIMIT 1 FOR UPDATE",
                shopId, idempotencyKey.trim());
        return rows.isEmpty() ? null : map(rows.get(0));
    }

    public Entry findByIdempotencyKey(int shopId, String idempotencyKey) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                selectColumns()
                        + "FROM t_payment_refund_request "
                        + "WHERE shop_id = ? AND idempotency_key = ? LIMIT 1",
                shopId, idempotencyKey.trim());
        return rows.isEmpty() ? null : map(rows.get(0));
    }

    /**
     * Lists pending (REQUESTED) refund requests for the compensation task.
     * Never locks: the settlement service locks via beginCallback before applying.
     */
    public List<Entry> findPending(int limit) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                selectColumns()
                        + "FROM t_payment_refund_request "
                        + "WHERE status = 'REQUESTED' "
                        + "ORDER BY id ASC LIMIT ?",
                Math.max(1, Math.min(limit, 500)));
        java.util.ArrayList<Entry> out = new java.util.ArrayList<>();
        for (Map<String, Object> row : rows) {
            out.add(map(row));
        }
        return out;
    }

    /**
     * Locks the callback ledger entry. Returns false when already applied.
     */
    public boolean beginCallback(
            int shopId,
            String orderNo,
            String outRefundNo,
            int requestedFen) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                selectColumns()
                        + "FROM t_payment_refund_request "
                        + "WHERE out_refund_no = ? LIMIT 1 FOR UPDATE",
                outRefundNo.trim());
        if (rows.isEmpty()) {
            throw new IllegalStateException("退款单未在本系统登记，禁止自动入账");
        }
        Entry entry = map(rows.get(0));
        if (number(rows.get(0).get("shop_id")) != shopId) {
            throw new IllegalStateException("退款单号与门店不匹配");
        }
        if (!orderNo.trim().equals(entry.orderNo)) {
            throw new IllegalStateException("退款单号与订单不匹配");
        }
        if (requestedFen != entry.requestedFen) {
            throw new IllegalStateException("退款回调金额与申请金额不匹配");
        }
        return !"SUCCESS".equals(entry.status);
    }

    /** 锁定并验证微信退款通知所对应的既有申请；未知退款不得由回调补建。 */
    public Entry beginVerifiedCallback(
            String outRefundNo,
            int refundFen,
            String transactionId,
            String mchId) {
        if (!StringUtils.hasText(outRefundNo) || refundFen <= 0) {
            throw new IllegalArgumentException("退款回调参数无效");
        }
        List<Map<String, Object>> rows = jdbc.queryForList(
                selectColumns() + "FROM t_payment_refund_request "
                        + "WHERE out_refund_no = ? LIMIT 1 FOR UPDATE",
                outRefundNo.trim());
        if (rows.isEmpty()) {
            throw new IllegalStateException("退款单未在本系统登记，禁止自动入账");
        }
        Entry entry = map(rows.get(0));
        if (refundFen != entry.requestedFen) {
            throw new IllegalStateException("退款回调金额与申请金额不匹配");
        }
        if (!StringUtils.hasText(entry.expectedTransactionId)
                || !entry.expectedTransactionId.equals(trimToNull(transactionId))) {
            throw new IllegalStateException("退款回调微信交易号与申请不匹配");
        }
        if (!StringUtils.hasText(entry.expectedMchId)
                || !entry.expectedMchId.equals(trimToNull(mchId))) {
            throw new IllegalStateException("退款回调商户号与申请不匹配");
        }
        if (entry.shopId <= 0 || entry.merchantConfigId == null
                || entry.merchantConfigVersion == null || entry.merchantConfigVersion <= 0) {
            throw new IllegalStateException("退款申请缺少门店或商户凭据绑定");
        }
        return entry;
    }

    public void markRequestFailed(int shopId, String idempotencyKey) {
        jdbc.update("UPDATE t_payment_refund_request SET status = 'FAILED' "
                        + "WHERE shop_id = ? AND idempotency_key = ? "
                        + "AND status = 'REQUESTED'",
                shopId, idempotencyKey.trim());
        jdbc.update("DELETE FROM t_payment_refund_guard "
                        + "WHERE shop_id = ? AND idempotency_key = ?",
                shopId, idempotencyKey.trim());
    }

    public void markSuccess(String outRefundNo, int appliedFen) {
        int updated = jdbc.update(
                "UPDATE t_payment_refund_request "
                        + "SET status = 'SUCCESS', applied_fen = ? "
                        + "WHERE out_refund_no = ?",
                appliedFen, outRefundNo.trim());
        if (updated != 1) {
            throw new IllegalStateException("退款幂等记录更新失败");
        }
        jdbc.update("DELETE g FROM t_payment_refund_guard g "
                        + "JOIN t_payment_refund_request r "
                        + "ON r.shop_id = g.shop_id "
                        + "AND r.idempotency_key = g.idempotency_key "
                        + "WHERE r.out_refund_no = ?",
                outRefundNo.trim());
    }

    private static Entry map(Map<String, Object> row) {
        return new Entry(
                String.valueOf(row.get("order_no")),
                String.valueOf(row.get("idempotency_key")),
                String.valueOf(row.get("out_refund_no")),
                number(row.get("requested_fen")),
                number(row.get("applied_fen")),
                String.valueOf(row.get("status")),
                number(row.get("shop_id")),
                longNumber(row.get("merchant_config_id")),
                integer(row.get("merchant_config_version")),
                nullableText(row.get("expected_transaction_id")),
                nullableText(row.get("expected_mch_id")));
    }

    private static String selectColumns() {
        return "SELECT shop_id, order_no, idempotency_key, out_refund_no, requested_fen, "
                + "applied_fen, status, merchant_config_id, merchant_config_version, "
                + "expected_transaction_id, expected_mch_id ";
    }

    private static int number(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }

    private static Long longNumber(Object value) {
        return value instanceof Number ? ((Number) value).longValue() : null;
    }

    private static Integer integer(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : null;
    }

    private static String nullableText(Object value) {
        return value == null ? null : trimToNull(String.valueOf(value));
    }

    private static String trimToNull(String value) {
        return StringUtils.hasText(value) ? value.trim() : null;
    }

    private static boolean sameNullable(Object left, Object right) {
        return left == null ? right == null : left.equals(right);
    }

    private static void validate(
            int shopId,
            String orderNo,
            String idempotencyKey,
            String outRefundNo,
            int requestedFen) {
        if (shopId <= 0
                || !StringUtils.hasText(orderNo)
                || !StringUtils.hasText(idempotencyKey)
                || !StringUtils.hasText(outRefundNo)
                || requestedFen <= 0) {
            throw new IllegalArgumentException("退款幂等参数无效");
        }
        if (idempotencyKey.trim().length() > 64
                || outRefundNo.trim().length() > 64) {
            throw new IllegalArgumentException("退款幂等键长度不能超过64");
        }
    }

    public static final class Entry {
        public final String orderNo;
        public final String idempotencyKey;
        public final String outRefundNo;
        public final int requestedFen;
        public final int appliedFen;
        public final String status;
        public final int shopId;
        public final Long merchantConfigId;
        public final Integer merchantConfigVersion;
        public final String expectedTransactionId;
        public final String expectedMchId;

        Entry(
                String orderNo,
                String idempotencyKey,
                String outRefundNo,
                int requestedFen,
                int appliedFen,
                String status) {
            this(orderNo, idempotencyKey, outRefundNo, requestedFen, appliedFen, status,
                    0, null, null, null, null);
        }

        Entry(
                String orderNo,
                String idempotencyKey,
                String outRefundNo,
                int requestedFen,
                int appliedFen,
                String status,
                int shopId,
                Long merchantConfigId,
                Integer merchantConfigVersion,
                String expectedTransactionId,
                String expectedMchId) {
            this.orderNo = orderNo;
            this.idempotencyKey = idempotencyKey;
            this.outRefundNo = outRefundNo;
            this.requestedFen = requestedFen;
            this.appliedFen = appliedFen;
            this.status = status;
            this.shopId = shopId;
            this.merchantConfigId = merchantConfigId;
            this.merchantConfigVersion = merchantConfigVersion;
            this.expectedTransactionId = expectedTransactionId;
            this.expectedMchId = expectedMchId;
        }

        public boolean isSuccessful() {
            return "SUCCESS".equals(status);
        }

        public boolean isRejected() {
            return "REJECTED".equals(status);
        }
    }
}
