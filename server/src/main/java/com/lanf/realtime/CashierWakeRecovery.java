package com.lanf.realtime;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Bounded polling of existing durable cursors recovers wakes produced by another JVM. */
@Component
public class CashierWakeRecovery {
    private final JdbcTemplate jdbc;
    private final CashierEventWebSocketHub hub;
    public CashierWakeRecovery(JdbcTemplate jdbc,CashierEventWebSocketHub hub) { this.jdbc=jdbc;this.hub=hub; }
    @Scheduled(fixedDelayString="${kds.wake-recovery-ms:5000}")
    public void recover() {
        for (Integer shop : hub.activeShops()) {
            Long cursor=jdbc.queryForObject("SELECT COALESCE(MAX(id),0) FROM t_kds_delivery_event WHERE shop_id=?",Long.class,shop);
            // Duplicate wakeups are intentional; clients pull/ack the durable cursor idempotently.
            if (cursor != null && cursor>0) hub.broadcastWake(shop,cursor);
        }
    }
}
