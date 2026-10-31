package com.lanf.kds.delivery;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.util.concurrent.*;

/** Dedicated bounded polling; slow unrelated scheduled integrations cannot suppress recovery. */
@Component
@ConditionalOnProperty(name = "app.scheduling.enabled", havingValue = "true", matchIfMissing = true)
public class CashierKdsProjectionIntentPoller {
    private static final Logger log = LoggerFactory.getLogger(CashierKdsProjectionIntentPoller.class);
    private final CashierKdsProjectionService service;
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread thread = new Thread(task, "kds-intent-poller");
        thread.setDaemon(true);
        return thread;
    });
    public CashierKdsProjectionIntentPoller(CashierKdsProjectionService service) { this.service = service; }
    @PostConstruct public void start() {
        timer.scheduleWithFixedDelay(() -> {
            try { service.dispatchPendingIntents(); }
            catch (Exception ex) { log.warn("[kds-intent] polling failed: {}", ex.getClass().getSimpleName()); }
        }, 5, 5, TimeUnit.SECONDS);
    }
    @PreDestroy public void close() { timer.shutdownNow(); }
}
