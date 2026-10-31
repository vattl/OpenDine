package com.lanf.kds.delivery;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Read-only guard; application startup must never silently fall back to volatile delivery. */
@Component
public class CashierKdsProjectionIntentReadiness implements ApplicationRunner {
    private final JdbcTemplate jdbc;
    public CashierKdsProjectionIntentReadiness(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    @Override public void run(ApplicationArguments args) {
        try {
            jdbc.queryForList("SELECT id,order_id,event_type,origin_channel,origin_device_code,changed_detail_ids_json,attempts,next_attempt_ms,created_at FROM t_kds_projection_intent WHERE 1=0");
            for (String index : new String[]{"PRIMARY", "idx_kds_intent_due", "idx_kds_intent_order"}) {
                Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_kds_projection_intent' AND INDEX_NAME=?", Integer.class, index);
                if (count == null || count == 0) throw new IllegalStateException("missing intent index " + index);
            }
            String engine = jdbc.queryForObject("SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_kds_projection_intent'", String.class);
            if (!"InnoDB".equalsIgnoreCase(engine)) throw new IllegalStateException("intent table must use InnoDB");
        } catch (Exception ex) {
            throw new IllegalStateException("Apply docs/db_migration_kds_projection_intent.sql before starting this version", ex);
        }
    }
}
