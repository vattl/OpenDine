package com.lanf.report.service;

import java.util.Set;
import java.util.concurrent.*;

/** A durable database row is the queue of record; this executor only holds bounded wakeups. */
public final class BoundedJobExecutor {
    private static final org.slf4j.Logger log=org.slf4j.LoggerFactory.getLogger(BoundedJobExecutor.class);
    private BoundedJobExecutor() { }
    public static ExecutorService create(String name) {
        return new ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(16), r -> {
            Thread thread = new Thread(r, name);
            thread.setDaemon(true);
            return thread;
        }, new ThreadPoolExecutor.AbortPolicy());
    }
    public static boolean submit(ExecutorService executor, Set<Long> scheduled, Long id, Runnable task) {
        if (!scheduled.add(id)) return true;
        try {
            executor.submit(() -> {
                try { task.run(); }
                catch (RuntimeException ex) { log.warn("durable job {} wakeup failed: {}",id,ex.getClass().getSimpleName()); }
                finally { scheduled.remove(id); }
            });
            return true;
        } catch (RejectedExecutionException ex) {
            scheduled.remove(id);
            return false;
        }
    }
}
