package com.lanf.payment.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;


import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Serializes manual QR collection for one order across cashier windows/devices.
 */
@Component
@org.springframework.context.annotation.DependsOn("paymentSchemaReadiness")
public class CashierCollectionIntentService {

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(CashierCollectionIntentService.class);

    public static final int PENDING_TTL_SECONDS = 180; // 3分钟出码生命周期
    private final JdbcTemplate jdbc;

    public CashierCollectionIntentService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }



    @Transactional(rollbackFor = Exception.class)
    public void reserve(
            int shopId,
            String orderNo,
            String sessionId,
            String channel,
            int amountFen) {
        validate(shopId, orderNo, sessionId, channel, amountFen);
        lockUnsettledOrder(shopId, orderNo);
        jdbc.update("INSERT IGNORE INTO t_cashier_collection_intent "
                        + "(shop_id, order_no, session_id, channel, amount_fen, expires_at) "
                        + "VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))",
                shopId, orderNo.trim(), sessionId.trim(), channel, amountFen,
                PENDING_TTL_SECONDS);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT session_id, channel, status, amount_fen, "
                        + "expires_at < NOW() AS expired "
                        + "FROM t_cashier_collection_intent "
                        + "WHERE shop_id = ? AND order_no = ? FOR UPDATE",
                shopId, orderNo.trim());
        if (rows.isEmpty()) {
            throw new IllegalStateException("收款占用创建失败");
        }
        Map<String, Object> row = null;
        for (Map<String, Object> candidate : rows) {
            String candidateStatus = String.valueOf(candidate.get("status"));
            if ("CONFIRMED".equals(candidateStatus)
                    && !sessionId.trim().equals(
                    String.valueOf(candidate.get("session_id")))) {
                throw new IllegalStateException(
                        "该订单已有其他收款会话确认到账，请先完成入账");
            }
            if (channel.equals(String.valueOf(candidate.get("channel")))) {
                row = candidate;
            }
        }
        if (row == null) {
            throw new IllegalStateException("收款占用创建失败");
        }
        String owner = String.valueOf(row.get("session_id"));
        String status = String.valueOf(row.get("status"));
        if ("CONFIRMED".equals(status)) {
            if (sessionId.trim().equals(owner)
                    && amountFen == number(row.get("amount_fen"))) {
                return;
            }
            throw new IllegalStateException("该订单已有人工确认到账的扫码款，请先完成入账");
        }
        jdbc.update("UPDATE t_cashier_collection_intent "
                        + "SET session_id = ?, expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND) "
                        + "WHERE shop_id = ? AND order_no = ? AND status = 'PENDING'",
                sessionId.trim(), PENDING_TTL_SECONDS, shopId, orderNo.trim());
        jdbc.update("UPDATE t_cashier_collection_intent "
                        + "SET session_id = ?, amount_fen = ?, status = 'PENDING', "
                        + "created_at = NOW(), "
                        + "expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND) "
                        + "WHERE shop_id = ? AND order_no = ? AND channel = ?",
                sessionId.trim(), amountFen, PENDING_TTL_SECONDS,
                shopId, orderNo.trim(), channel);
    }

    @Transactional(rollbackFor = Exception.class)
    public int confirm(
            int shopId,
            String orderNo,
            String sessionId,
            String channel,
            int clientAmountFen) {
        validate(shopId, orderNo, sessionId, channel, clientAmountFen);
        lockUnsettledOrder(shopId, orderNo);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT session_id, status, amount_fen, expires_at < NOW() AS expired "
                        + "FROM t_cashier_collection_intent "
                        + "WHERE shop_id = ? AND order_no = ? AND channel = ? "
                        + "LIMIT 1 FOR UPDATE",
                shopId, orderNo.trim(), channel);
        if (rows.isEmpty()) {
            throw new IllegalStateException("收款码尚未生成或已失效");
        }
        Map<String, Object> row = rows.get(0);
        String owner = String.valueOf(row.get("session_id"));
        String status = String.valueOf(row.get("status"));
        int reservedAmountFen = number(row.get("amount_fen"));
        if (!sessionId.trim().equals(owner)) {
            throw new IllegalStateException("收款会话不匹配，请重新获取收款码");
        }
        if ("CONFIRMED".equals(status) || "COMPLETED".equals(status)) {
            return reservedAmountFen;
        }
        if (!"PENDING".equals(status) || number(row.get("expired")) == 1) {
            throw new IllegalStateException("收款码已失效，请重新生成");
        }
        int updated = jdbc.update(
                "UPDATE t_cashier_collection_intent "
                        + "SET status = 'CONFIRMED', expires_at = '9999-12-31 23:59:59' "
                        + "WHERE shop_id = ? AND order_no = ? AND channel = ? "
                        + "AND session_id = ? AND status = 'PENDING'",
                shopId, orderNo.trim(), channel, sessionId.trim());
        if (updated != 1) {
            throw new IllegalStateException("确认收款失败，请重新核对");
        }
        return reservedAmountFen;
    }

    /**
     * 直接置为已确认到账状态（用于出码补偿前置匹配到账记录后无缝复用收银结账流程）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void confirmDirect(
            int shopId,
            String orderNo,
            String sessionId,
            String channel,
            int amountFen) {
        validate(shopId, orderNo, sessionId, channel, amountFen);
        lockUnsettledOrder(shopId, orderNo);
        jdbc.update("INSERT INTO t_cashier_collection_intent "
                        + "(shop_id, order_no, session_id, channel, amount_fen, status, expires_at) "
                        + "VALUES (?, ?, ?, ?, ?, 'CONFIRMED', '9999-12-31 23:59:59') "
                        + "ON DUPLICATE KEY UPDATE session_id = VALUES(session_id), "
                        + "amount_fen = VALUES(amount_fen), status = 'CONFIRMED', expires_at = '9999-12-31 23:59:59'",
                shopId, orderNo.trim(), sessionId.trim(), channel.trim().toLowerCase(), amountFen);
    }

    /**
     * Called after locking the order row and before any wallet mutation.
     */
    public void validateCheckout(
            int shopId,
            String orderNo,
            String sessionId,
            int wechatFen,
            int alipayFen) {
        validateCheckout(shopId, orderNo, sessionId, wechatFen, alipayFen, false);
    }

    public void validateCheckout(
            int shopId,
            String orderNo,
            String sessionId,
            int wechatFen,
            int alipayFen,
            boolean force) {
        if (force) {
            log.info("强制结账模式：跳过收款意向强一致性校验 orderNo={}, shopId={}, sessionId={}",
                    orderNo, shopId, sessionId);
            cancelAllPending(shopId, orderNo);
            return;
        }
        Map<String, Integer> expected = new HashMap<>();
        if (wechatFen > 0) expected.put("wechat", wechatFen);
        if (alipayFen > 0) expected.put("alipay", alipayFen);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT session_id, channel, amount_fen, status, "
                        + "expires_at < NOW() AS expired "
                        + "FROM t_cashier_collection_intent "
                        + "WHERE shop_id = ? AND order_no = ? AND status <> 'COMPLETED' "
                        + "FOR UPDATE",
                shopId, orderNo.trim());
        Map<String, Map<String, Object>> confirmed = new HashMap<>();
        for (Map<String, Object> row : rows) {
            String status = String.valueOf(row.get("status"));
            if ("CONFIRMED".equals(status)) {
                confirmed.put(String.valueOf(row.get("channel")), row);
            }
        }
        if (expected.isEmpty()) {
            if (!confirmed.isEmpty()) {
                throw new IllegalStateException("该订单已有扫码款确认到账，不能更换为其他支付方式");
            }
            cancelAllPending(shopId, orderNo);
            return;
        }
        if (!StringUtils.hasText(sessionId)) {
            throw new IllegalStateException("扫码结账缺少收款会话");
        }
        for (Map.Entry<String, Map<String, Object>> item : confirmed.entrySet()) {
            Integer expectedFen = expected.get(item.getKey());
            Map<String, Object> row = item.getValue();
            if (expectedFen == null) {
                throw new IllegalStateException("已有其他扫码渠道确认到账，不能更换支付方式");
            }
            if (!sessionId.trim().equals(String.valueOf(row.get("session_id")))
                    || expectedFen != number(row.get("amount_fen"))) {
                throw new IllegalStateException("已确认扫码款的收款会话或金额不匹配");
            }
        }
        for (Map.Entry<String, Integer> item : expected.entrySet()) {
            Map<String, Object> row = confirmed.get(item.getKey());
            if (row == null
                    || !sessionId.trim().equals(String.valueOf(row.get("session_id")))
                    || item.getValue() != number(row.get("amount_fen"))) {
                throw new IllegalStateException("扫码款尚未确认到账或金额不匹配");
            }
        }
        cancelAllPending(shopId, orderNo);
    }

    public void complete(int shopId, String orderNo, String sessionId) {
        if (!StringUtils.hasText(sessionId)) {
            return;
        }
        jdbc.update("UPDATE t_cashier_collection_intent SET status = 'COMPLETED' "
                        + "WHERE shop_id = ? AND order_no = ? AND session_id = ? "
                        + "AND status = 'CONFIRMED'",
                shopId, orderNo.trim(), sessionId.trim());
    }

    /**
     * 将指定订单名下所有尚未归档（PENDING、CONFIRMED）的收款意向原子收敛标记为 COMPLETED。
     * 用于强制结账或后台结账完成后的统一资源清理，避免残留的意向会话阻断后续订单或退款操作。
     */
    public int completeAllForOrder(int shopId, String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return 0;
        }
        return jdbc.update("UPDATE t_cashier_collection_intent SET status = 'COMPLETED' "
                        + "WHERE shop_id = ? AND order_no = ? "
                        + "AND status IN ('PENDING', 'CONFIRMED')",
                shopId, orderNo.trim());
    }

    /**
     * 将指定订单名下所有未完成（PENDING）收款意向原子置为 CANCELLED。
     * 用于订单作废/取消时清理占用的收款意向。
     */
    public int cancelAllForOrder(int shopId, String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return 0;
        }
        return jdbc.update("UPDATE t_cashier_collection_intent SET status = 'CANCELLED', expires_at = NOW() "
                        + "WHERE shop_id = ? AND order_no = ? "
                        + "AND status = 'PENDING'",
                shopId, orderNo.trim());
    }

    public static class AmbiguousCollectionException extends IllegalStateException {
        public AmbiguousCollectionException() { super("同金额存在多个收款意向，需人工核对"); }
    }

    public static class MatchedIntent {
        private Long id;
        private Integer shopId;
        private String orderNo;
        private String sessionId;
        private Date createdAt;

        public MatchedIntent() {}

        public MatchedIntent(Long id, Integer shopId, String orderNo, String sessionId, Date createdAt) {
            this.id = id;
            this.shopId = shopId;
            this.orderNo = orderNo;
            this.sessionId = sessionId;
            this.createdAt = createdAt;
        }

        public Long getId() { return id; }
        public void setId(Long id) { this.id = id; }
        public Integer getShopId() { return shopId; }
        public void setShopId(Integer shopId) { this.shopId = shopId; }
        public String getOrderNo() { return orderNo; }
        public void setOrderNo(String orderNo) { this.orderNo = orderNo; }
        public String getSessionId() { return sessionId; }
        public void setSessionId(String sessionId) { this.sessionId = sessionId; }
        public Date getCreatedAt() { return createdAt; }
        public void setCreatedAt(Date createdAt) { this.createdAt = createdAt; }
    }

    /**
     * 当收到个人收款通知回调时，在出码后 3 分钟（180秒）有效时间窗口内自动查找并确认匹配的收款意向。
     */
    @Transactional(rollbackFor = Exception.class)
    public MatchedIntent matchAndConfirmByWebhook(Integer shopId, String channel, int amountFen, Date arrivalTime) {
        if (shopId == null || shopId <= 0 || !StringUtils.hasText(channel) || amountFen <= 0 || arrivalTime == null) {
            return null;
        }
        // Never infer a shop or choose the closest of several same-amount payments.
        Date latestStart = new Date(arrivalTime.getTime() + 15_000L);
        Date earliestExpiry = new Date(arrivalTime.getTime() - 15_000L);
        String sql = "SELECT id, shop_id, order_no, session_id, created_at FROM t_cashier_collection_intent "
                + "WHERE shop_id = ? AND channel = ? AND amount_fen = ? AND status = 'PENDING' "
                + "AND created_at <= ? AND expires_at >= ? ORDER BY id LIMIT 2 FOR UPDATE";
        List<Map<String, Object>> list = jdbc.queryForList(sql,
                shopId, channel.trim().toLowerCase(java.util.Locale.ROOT), amountFen, latestStart, earliestExpiry);
        if (list.size() > 1) throw new AmbiguousCollectionException();
        if (list.isEmpty()) return null;
        Map<String, Object> row = list.get(0);
        Long id = ((Number) row.get("id")).longValue();
        Integer matchedShopId = ((Number) row.get("shop_id")).intValue();
        String orderNo = String.valueOf(row.get("order_no"));
        String sessionId = String.valueOf(row.get("session_id"));
        Date createdAt = row.get("created_at") instanceof Date ? (Date) row.get("created_at") : new Date();
        jdbc.update("UPDATE t_cashier_collection_intent SET status = 'CONFIRMED', expires_at = '9999-12-31 23:59:59' WHERE id = ?", id);
        return new MatchedIntent(id, matchedShopId, orderNo, sessionId, createdAt);
    }

    /**
     * 向后兼容查找确认接口
     */
    @Transactional(rollbackFor = Exception.class)
    public String confirmByWebhook(Integer shopId, String channel, int amountFen) {
        MatchedIntent matched = matchAndConfirmByWebhook(shopId, channel, amountFen, new Date());
        return matched != null ? matched.getOrderNo() : null;
    }

    /** Releases only the caller-owned, unconfirmed collection lease. */
    @Transactional(rollbackFor = Exception.class)
    public int cancelPending(
            int shopId,
            String orderNo,
            String sessionId,
            String channel) {
        validateSession(shopId, orderNo, sessionId, channel);

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, status FROM t_cashier_collection_intent "
                        + "WHERE shop_id = ? AND order_no = ? AND session_id = ? AND channel = ? "
                        + "LIMIT 1 FOR UPDATE",
                shopId, orderNo.trim(), sessionId.trim(), channel.trim().toLowerCase());
        if (!rows.isEmpty()) {
            String status = String.valueOf(rows.get(0).get("status"));
            if ("COMPLETED".equalsIgnoreCase(status) || "CANCELLED".equalsIgnoreCase(status)) {
                // 已完成结账或已释放，直接返回成功释放
                return 1;
            }
            if ("CONFIRMED".equalsIgnoreCase(status)) {
                throw new IllegalStateException("该订单已有扫码款确认到账，不能取消");
            }
        }

        List<Map<String, Object>> orderRows = jdbc.queryForList(
                "SELECT transac_status FROM t_order "
                        + "WHERE shop_id = ? AND order_no = ? LIMIT 1 FOR UPDATE",
                shopId, orderNo.trim());
        if (orderRows.isEmpty()) {
            List<Map<String, Object>> globalRows = jdbc.queryForList(
                    "SELECT shop_id, transac_status FROM t_order WHERE order_no = ? LIMIT 1",
                    orderNo.trim());
            if (globalRows.isEmpty()) {
                throw new IllegalStateException("订单不存在");
            } else {
                throw new IllegalStateException("订单不属于当前门店");
            }
        }
        String orderStatus = String.valueOf(orderRows.get(0).get("transac_status"));
        if ("success".equalsIgnoreCase(orderStatus)) {
            // 订单已结账，自动关闭当前未完成出码意向并返回成功释放
            jdbc.update("UPDATE t_cashier_collection_intent "
                            + "SET status = 'CANCELLED', expires_at = NOW() "
                            + "WHERE shop_id = ? AND order_no = ? AND session_id = ? "
                            + "AND channel = ? AND status = 'PENDING'",
                    shopId, orderNo.trim(), sessionId.trim(), channel.trim().toLowerCase());
            return 1;
        }
        if ("cancelled".equalsIgnoreCase(orderStatus)) {
            throw new IllegalStateException("订单已取消");
        }
        if (!"unsettled".equalsIgnoreCase(orderStatus)) {
            throw new IllegalStateException("订单状态不是未结账状态（当前状态：" + orderStatus + "）");
        }

        return jdbc.update("UPDATE t_cashier_collection_intent "
                        + "SET status = 'CANCELLED', expires_at = NOW() "
                        + "WHERE shop_id = ? AND order_no = ? AND session_id = ? "
                        + "AND channel = ? AND status = 'PENDING'",
                shopId, orderNo.trim(), sessionId.trim(), channel.trim().toLowerCase());
    }

    private void cancelAllPending(int shopId, String orderNo) {
        jdbc.update("UPDATE t_cashier_collection_intent "
                        + "SET status = 'CANCELLED', expires_at = NOW() "
                        + "WHERE shop_id = ? AND order_no = ? AND status = 'PENDING'",
                shopId, orderNo.trim());
    }

    private void lockUnsettledOrder(int shopId, String orderNo) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT transac_status FROM t_order "
                        + "WHERE shop_id = ? AND order_no = ? LIMIT 1 FOR UPDATE",
                shopId, orderNo.trim());
        if (rows.isEmpty()) {
            List<Map<String, Object>> globalRows = jdbc.queryForList(
                    "SELECT shop_id, transac_status FROM t_order WHERE order_no = ? LIMIT 1",
                    orderNo.trim());
            if (globalRows.isEmpty()) {
                throw new IllegalStateException("订单不存在");
            } else {
                throw new IllegalStateException("订单不属于当前门店");
            }
        }
        String status = String.valueOf(rows.get(0).get("transac_status"));
        if ("success".equalsIgnoreCase(status)) {
            throw new IllegalStateException("订单已结账");
        }
        if ("cancelled".equalsIgnoreCase(status)) {
            throw new IllegalStateException("订单已取消");
        }
        if (!"unsettled".equalsIgnoreCase(status)) {
            throw new IllegalStateException("订单状态不是未结账状态（当前状态：" + status + "）");
        }
    }

    private static void validate(
            int shopId,
            String orderNo,
            String sessionId,
            String channel,
            int amountFen) {
        if (shopId <= 0
                || !StringUtils.hasText(orderNo)
                || !StringUtils.hasText(sessionId)
                || sessionId.trim().length() > 64
                || (!"wechat".equals(channel) && !"alipay".equals(channel))
                || amountFen <= 0) {
            throw new IllegalArgumentException("收款占用参数无效");
        }
    }

    private static void validateSession(
            int shopId,
            String orderNo,
            String sessionId,
            String channel) {
        if (shopId <= 0
                || !StringUtils.hasText(orderNo)
                || !StringUtils.hasText(sessionId)
                || sessionId.trim().length() > 64
                || (!"wechat".equals(channel) && !"alipay".equals(channel))) {
            throw new IllegalArgumentException("收款取消参数无效");
        }
    }

    private static int number(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }
}
