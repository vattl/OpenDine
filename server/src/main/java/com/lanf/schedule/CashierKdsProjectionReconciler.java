package com.lanf.schedule;

import com.lanf.kds.delivery.CashierKdsProjectionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.sql.Timestamp;

import java.util.List;
import java.util.Collections;
import java.util.concurrent.*;

/** 补偿事务钩子、进程重启或短暂数据库故障导致的厨房投影漏写。 */
@Component
@ConditionalOnProperty(name = "app.scheduling.enabled", havingValue = "true", matchIfMissing = true)
public class CashierKdsProjectionReconciler {
    private static final Logger log = LoggerFactory.getLogger(CashierKdsProjectionReconciler.class);
    private final JdbcTemplate jdbc;
    private final CashierKdsProjectionService projectionService;
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread thread = new Thread(task, "kds-projection-compensation"); thread.setDaemon(true); return thread;
    });
    @Value("${kds.projection-reconcile-interval-ms:30000}") private long intervalMs = 30_000L;
    @Value("${kds.projection-reconcile-batch-size:32}") private int batchSize = 32;
    @Value("${kds.projection-reconcile-budget-ms:10000}") private long budgetMs = 10_000L;
    @Value("${kds.event-cleanup-batch-size:200}") private int cleanupBatchSize = 200;
    @Value("${kds.event-cleanup-budget-ms:5000}") private long cleanupBudgetMs = 5_000L;
    private volatile int cursor;

    public CashierKdsProjectionReconciler(JdbcTemplate jdbc, CashierKdsProjectionService projectionService) {
        this.jdbc = jdbc; this.projectionService = projectionService;
    }

    @PostConstruct public void start() {
        worker.scheduleWithFixedDelay(this::reconcile, 30_000L, intervalMs, TimeUnit.MILLISECONDS);
        worker.scheduleWithFixedDelay(this::cleanupAcknowledgedEvents, 3_600_000L, 3_600_000L, TimeUnit.MILLISECONDS);
    }

    public void reconcile() {
        List<Integer> orderIds;
        int limit = Math.max(1, Math.min(batchSize, 100));
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(Math.max(1_000L, budgetMs));
        try {
            orderIds = jdbc.queryForList("SELECT o.id FROM t_order o LEFT JOIN t_kds_order_projection p ON p.order_id=o.id "
                    + "WHERE o.shop_id IS NOT NULL AND o.order_time>=? "
                    + "AND (o.order_receiving IN ('rec_order','mis_order','mis_orders','off_order','cancelled') OR o.transac_status='cancelled') "
                    + "AND o.id>? ORDER BY o.id ASC LIMIT ?", Integer.class,
                    new Timestamp(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(2)), cursor, limit);
        } catch (Exception ex) {
            log.debug("[cashier-kds-delivery] reconciliation unavailable: {}", ex.getMessage());
            return;
        }
        int repaired = 0;
        boolean budgetExhausted = false;
        for (Integer orderId : orderIds) {
            if (System.nanoTime() >= deadline) { budgetExhausted = true; break; }
            cursor = orderId;
            try {
                if (projectionService.publish(orderId, "ORDER_UPDATED", null, null, null) != null) repaired++;
            } catch (Exception ex) {
                log.warn("[cashier-kds-delivery] reconcile failed order={}: {}", orderId, ex.getMessage());
            }
        }
        if (!budgetExhausted && orderIds.size() < limit) cursor = 0; // wrap only after the cursor reaches the current end
        if (repaired > 0) log.info("[cashier-kds-delivery] reconciliation persisted {} event(s)", repaired);
    }

    public void cleanupAcknowledgedEvents() {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(Math.max(1000L, cleanupBudgetMs));
        int limit = Math.max(1, Math.min(1000, cleanupBatchSize));
        int removedTotal = 0;
        try {
            while (System.nanoTime() < deadline) {
                List<Long> ids = jdbc.queryForList("SELECT e.id FROM t_kds_delivery_event e "
                        + "JOIN t_kds_delivery_consumer c ON c.shop_id=e.shop_id "
                        + "WHERE e.id<=c.ack_cursor AND e.created_at<? ORDER BY e.id LIMIT ?", Long.class,
                        new Timestamp(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(7)), limit);
                if (ids.isEmpty()) break;
                String placeholders = String.join(",", Collections.nCopies(ids.size(), "?"));
                removedTotal += jdbc.update("DELETE FROM t_kds_delivery_event WHERE id IN (" + placeholders + ")", ids.toArray());
                if (ids.size() < limit) break;
            }
            if (removedTotal > 0) log.info("[cashier-kds-delivery] removed {} acknowledged event(s) past retention", removedTotal);
        } catch (Exception ex) {
            log.debug("[cashier-kds-delivery] retention cleanup unavailable: {}", ex.getMessage());
        }
    }

    @PreDestroy public void close() { worker.shutdownNow(); }
}
