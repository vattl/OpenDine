package com.lanf.kds.delivery;

import com.alibaba.druid.pool.DruidDataSource;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.realtime.CashierEventWebSocketHub;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.transaction.support.*;

import java.util.Collection;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

class CashierKdsProjectionPoolTest {
    @Test
    void fullPoolCommitsReturnAndBothProjectionsEventuallyAcquireConnections() throws Exception {
        DruidDataSource pool = new DruidDataSource();
        pool.setUrl("jdbc:h2:mem:projection-pool-" + System.nanoTime());
        pool.setDriverClassName("org.h2.Driver");
        pool.setMaxActive(2);
        pool.setMaxWait(300);
        pool.setValidationQuery("SELECT 1");
        JdbcTemplate jdbc = new JdbcTemplate(pool);
        jdbc.execute("CREATE TABLE t_kds_projection_intent (id BIGINT AUTO_INCREMENT PRIMARY KEY, order_id INT, event_type VARCHAR(32), origin_channel VARCHAR(24), origin_device_code VARCHAR(64), changed_detail_ids_json TEXT, attempts INT DEFAULT 0, next_attempt_ms BIGINT DEFAULT 0)");
        DataSourceTransactionManager manager = new DataSourceTransactionManager(pool);
        CountDownLatch bothCommitted = new CountDownLatch(2);
        CountDownLatch published = new CountDownLatch(2);
        CashierKdsProjectionPublishRetry retry = new CashierKdsProjectionPublishRetry(mock(TaskScheduler.class));
        CashierKdsProjectionService service = new CashierKdsProjectionService(
                jdbc, new ObjectMapper(), mock(CashierEventWebSocketHub.class), manager, retry) {
            @Override public Long publish(int id, String type, String channel, String device, Collection<Integer> details) {
                jdbc.queryForObject("SELECT 1", Integer.class);
                published.countDown();
                return 1L;
            }
        };
        ExecutorService callers = Executors.newFixedThreadPool(2);
        java.util.concurrent.atomic.AtomicInteger ids = new java.util.concurrent.atomic.AtomicInteger();
        try {
            Runnable create = () -> new TransactionTemplate(manager).execute(status -> {
                jdbc.queryForObject("SELECT 1", Integer.class);
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override public void afterCommit() {
                        bothCommitted.countDown();
                        try { assertTrue(bothCommitted.await(2, TimeUnit.SECONDS)); }
                        catch (InterruptedException ex) { Thread.currentThread().interrupt(); throw new AssertionError(ex); }
                    }
                });
                service.publishAfterCommit(ids.incrementAndGet(), "ORDER_UPDATED", null, null, null);
                return null;
            });
            Future<?> first = callers.submit(create);
            Future<?> second = callers.submit(create);
            first.get(3, TimeUnit.SECONDS);
            second.get(3, TimeUnit.SECONDS);
            assertTrue(published.await(2, TimeUnit.SECONDS), "both projections must succeed without waiting for pool timeout/retry");
            CashierKdsProjectionPublishRetry rollbackRetry = mock(CashierKdsProjectionPublishRetry.class);
            CashierKdsProjectionService rollbackService = new CashierKdsProjectionService(
                    jdbc, new ObjectMapper(), mock(CashierEventWebSocketHub.class), manager, rollbackRetry);
            new TransactionTemplate(manager).execute(status -> {
                jdbc.queryForObject("SELECT 1", Integer.class);
                rollbackService.publishAfterCommit(2, "ORDER_UPDATED", null, null, null);
                status.setRollbackOnly();
                return null;
            });
            org.mockito.Mockito.verifyNoInteractions(rollbackRetry);
        } finally {
            callers.shutdownNow();
            retry.close();
            pool.close();
        }
    }
}
