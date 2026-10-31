package com.lanf.payment.service;

import com.lanf.service.IUserService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;


import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.Map;

/**
 * Durable compensation queue for invite rewards that cannot be clawed back
 * immediately because the inviter has already spent the gift balance.
 */
@Component
@org.springframework.context.annotation.DependsOn("paymentSchemaReadiness")
public class InviteRewardClawbackService {

    private final JdbcTemplate jdbc;
    private final TransactionTemplate transactionTemplate;
    private final IUserService userService;

    public InviteRewardClawbackService(
            JdbcTemplate jdbc,
            TransactionTemplate transactionTemplate,
            IUserService userService) {
        this.jdbc = jdbc;
        this.transactionTemplate = transactionTemplate;
        this.userService = userService;
    }



    public void recordDebt(
            long inviteRecordId,
            int inviterUserId,
            String orderNo,
            BigDecimal amountYuan) {
        BigDecimal amount = amountYuan.setScale(2, RoundingMode.HALF_UP);
        if (amount.compareTo(BigDecimal.ZERO) <= 0) return;
        jdbc.update("INSERT INTO t_invite_reward_clawback "
                        + "(invite_record_id, inviter_user_id, order_no, "
                        + "outstanding_amount, status) VALUES (?, ?, ?, ?, 'PENDING') "
                        + "ON DUPLICATE KEY UPDATE "
                        + "outstanding_amount = outstanding_amount + VALUES(outstanding_amount), "
                        + "status = 'PENDING', last_error = NULL",
                inviteRecordId, inviterUserId, orderNo, amount);
    }

    @Scheduled(fixedDelayString = "${invite.clawback-retry-ms:300000}")
    public void retryPending() {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id FROM t_invite_reward_clawback "
                        + "WHERE status = 'PENDING' ORDER BY updated_at ASC LIMIT 100");
        for (Map<String, Object> row : rows) {
            Object value = row.get("id");
            if (value instanceof Number) {
                processOne(((Number) value).longValue());
            }
        }
    }

    private void processOne(long id) {
        transactionTemplate.executeWithoutResult(status -> {
            List<Map<String, Object>> rows = jdbc.queryForList(
                    "SELECT inviter_user_id, outstanding_amount, status "
                            + "FROM t_invite_reward_clawback "
                            + "WHERE id = ? LIMIT 1 FOR UPDATE",
                    id);
            if (rows.isEmpty()
                    || !"PENDING".equals(String.valueOf(rows.get(0).get("status")))) {
                return;
            }
            Map<String, Object> row = rows.get(0);
            int userId = ((Number) row.get("inviter_user_id")).intValue();
            BigDecimal amount = new BigDecimal(
                    String.valueOf(row.get("outstanding_amount")));
            if (userService.subtractGiftBalanceIfEnough(userId, amount)) {
                jdbc.update("UPDATE t_invite_reward_clawback "
                                + "SET status = 'COMPLETED', outstanding_amount = 0, "
                                + "attempts = attempts + 1, "
                                + "last_error = NULL WHERE id = ?",
                        id);
            } else {
                jdbc.update("UPDATE t_invite_reward_clawback "
                                + "SET attempts = attempts + 1, "
                                + "last_error = '赠送金余额不足，等待后续重试' WHERE id = ?",
                        id);
            }
        });
    }
}
