package com.lanf.schedule;

import com.lanf.config.ZsqSystemSettings;
import com.lanf.service.ITakeoutZsqIntegrationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.util.concurrent.*;

/**
 * 轮询真省钱配送状态，回写 t_takeout_delivery。
 */
@Component
@ConditionalOnProperty(name = "app.scheduling.enabled", havingValue = "true", matchIfMissing = true)
public class TakeoutZsqSyncScheduler {

    private static final Logger log = LoggerFactory.getLogger(TakeoutZsqSyncScheduler.class);

    private final ITakeoutZsqIntegrationService takeoutZsqIntegrationService;
    private final ZsqSystemSettings zsqSystemSettings;
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread thread = new Thread(task, "takeout-delivery-sync"); thread.setDaemon(true); return thread;
    });
    @Value("${zsq.takeout-sync-interval-ms:60000}") private long intervalMs = 60_000L;
    @Value("${zsq.takeout-sync-batch-size:20}") private int batchSize = 20;
    @Value("${zsq.takeout-sync-budget-ms:20000}") private long budgetMs = 20_000L;
    private volatile long cursor;

    public TakeoutZsqSyncScheduler(ITakeoutZsqIntegrationService takeoutZsqIntegrationService,
                                   ZsqSystemSettings zsqSystemSettings) {
        this.takeoutZsqIntegrationService = takeoutZsqIntegrationService;
        this.zsqSystemSettings = zsqSystemSettings;
    }

    @PostConstruct
    public void start() {
        worker.scheduleWithFixedDelay(this::syncActiveDeliveries, intervalMs, intervalMs, TimeUnit.MILLISECONDS);
    }

    public void syncActiveDeliveries() {
        if (!zsqSystemSettings.isTakeoutSyncEnabled()) {
            return;
        }
        try {
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(Math.max(1_000L, budgetMs));
            ITakeoutZsqIntegrationService.DeliverySyncBatch batch =
                    takeoutZsqIntegrationService.syncActiveDeliveriesAfter(cursor, batchSize, deadline);
            cursor = batch.exhausted ? 0 : batch.lastId;
            if (batch.processed > 0) {
                log.debug("真省钱外卖状态同步完成: {} 条, cursor={}", batch.processed, cursor);
            }
        } catch (Exception e) {
            log.warn("真省钱外卖状态同步任务异常: {}", e.getMessage());
        }
    }

    @PreDestroy public void close() { worker.shutdownNow(); }
}
