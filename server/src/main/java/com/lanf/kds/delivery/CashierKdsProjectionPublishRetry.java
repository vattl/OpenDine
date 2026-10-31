package com.lanf.kds.delivery;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.stereotype.Component;

import java.util.Date;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import javax.annotation.PreDestroy;

/** Provides short, non-blocking retries before the durable reconciler takes over. */
@Component
public class CashierKdsProjectionPublishRetry {
    private static final Logger log = LoggerFactory.getLogger(CashierKdsProjectionPublishRetry.class);
    private static final long[] RETRY_DELAYS_MS = {1_000L, 3_000L};

    private final TaskScheduler scheduler;
    private final ThreadPoolExecutor workers = new ThreadPoolExecutor(2, 2, 0L, TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<>(128), task -> {
                Thread thread = new Thread(task, "kds-projection-worker");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());
    // Includes delayed retries: bounding only the executor queue would leave timer callbacks unbounded.
    private final Semaphore outstanding = new Semaphore(130);
    private final AtomicLong rejected = new AtomicLong();

    @Autowired
    public CashierKdsProjectionPublishRetry(
            @Qualifier("taskScheduler") ObjectProvider<TaskScheduler> schedulerProvider) {
        this.scheduler = schedulerProvider.getIfAvailable();
    }

    CashierKdsProjectionPublishRetry(TaskScheduler scheduler) {
        this.scheduler = scheduler;
    }

    // Package-private synchronous attempt seam for retry timing tests; production uses submit.
    void execute(int orderId, Runnable publish) {
        runAttempt(orderId, publish, 0, () -> { });
    }

    /** Never runs JDBC on the submitting (possibly post-commit) thread. */
    public boolean submit(int orderId, Runnable publish) {
        if (workers.isShutdown() || !outstanding.tryAcquire()) {
            recordRejection(orderId);
            return false;
        }
        return enqueue(orderId, publish, 0, outstanding::release);
    }

    private boolean enqueue(int orderId, Runnable publish, int attempt, Runnable finished) {
        try {
            workers.execute(() -> runAttempt(orderId, publish, attempt, finished));
            return true;
        } catch (RejectedExecutionException ex) {
            finished.run();
            recordRejection(orderId);
            return false;
        }
    }

    private void recordRejection(int orderId) {
        long count = rejected.incrementAndGet();
        if ((count & (count - 1)) == 0) {
            log.warn("[cashier-kds-delivery] projection queue full/closed order={} rejected={}; source-order reconciliation required",
                    orderId, count);
        }
    }

    public long rejectedCount() { return rejected.get(); }

    @PreDestroy
    public void close() { workers.shutdownNow(); }

    private void runAttempt(int orderId, Runnable publish, int attempt, Runnable finished) {
        try {
            publish.run();
        } catch (Error fatal) {
            finished.run();
            throw fatal;
        } catch (Exception ex) {
            if (attempt >= RETRY_DELAYS_MS.length) {
                log.warn("[cashier-kds-delivery] projection publish exhausted short retries order={}: {}",
                        orderId, ex.getMessage());
                finished.run();
                return;
            }
            long delayMs = RETRY_DELAYS_MS[attempt];
            log.warn("[cashier-kds-delivery] projection publish failed order={}, retryInMs={}: {}",
                    orderId, delayMs, ex.getMessage());
            if (scheduler == null) {
                log.warn("[cashier-kds-delivery] short retry scheduler unavailable order={}; durable reconciliation remains active",
                        orderId);
                finished.run();
                return;
            }
            try {
                if (scheduler.schedule(
                        () -> enqueue(orderId, publish, attempt + 1, finished),
                        new Date(System.currentTimeMillis() + delayMs)) == null) {
                    finished.run();
                }
            } catch (Exception scheduleFailure) {
                log.warn("[cashier-kds-delivery] short retry scheduling failed order={}: {}",
                        orderId, scheduleFailure.getMessage());
                finished.run();
            }
            return;
        }
        finished.run();
    }
}
