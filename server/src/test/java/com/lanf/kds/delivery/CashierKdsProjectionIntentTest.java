package com.lanf.kds.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.realtime.CashierEventWebSocketHub;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.Collection;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class CashierKdsProjectionIntentTest {
    JdbcTemplate jdbc;
    DataSourceTransactionManager manager;
    CashierKdsProjectionPublishRetry dispatcher;
    CashierKdsProjectionService service;
    boolean fail;

    @BeforeEach void setup() {
        DriverManagerDataSource ds = new DriverManagerDataSource(
                "jdbc:h2:mem:intent-" + System.nanoTime() + ";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "");
        jdbc = new JdbcTemplate(ds);
        manager = new DataSourceTransactionManager(ds);
        jdbc.execute("CREATE TABLE t_kds_projection_intent (id BIGINT AUTO_INCREMENT PRIMARY KEY, order_id INT, event_type VARCHAR(32), origin_channel VARCHAR(24), origin_device_code VARCHAR(64), changed_detail_ids_json TEXT, attempts INT DEFAULT 0, next_attempt_ms BIGINT DEFAULT 0, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE receipts(order_id INT)");
        dispatcher = mock(CashierKdsProjectionPublishRetry.class); // every wake rejected; durable row must survive
        service = newService();
    }

    CashierKdsProjectionService newService() {
        return new CashierKdsProjectionService(jdbc, new ObjectMapper(), mock(CashierEventWebSocketHub.class), manager, dispatcher) {
            @Override public Long publish(int id, String event, String channel, String device, Collection<Integer> details) {
                jdbc.update("INSERT INTO receipts VALUES (?)", id);
                if (fail) throw new IllegalStateException("simulated write failure");
                return 1L;
            }
        };
    }

    @AfterEach void cleanup() { jdbc.execute("SET DB_CLOSE_DELAY 0"); }

    @Test void rollbackLeavesNoIntentAndRejectedWakeRetainsCommittedIntent() {
        new TransactionTemplate(manager).execute(s -> {
            service.publishAfterCommit(1, "ORDER_UPDATED", null, null, null);
            assertEquals(1, count("t_kds_projection_intent"));
            s.setRollbackOnly(); return null;
        });
        assertEquals(0, count("t_kds_projection_intent"));
        verifyNoInteractions(dispatcher);
        service.publishAfterCommit(2, "ORDER_UPDATED", null, null, null);
        assertEquals(1, count("t_kds_projection_intent"));
    }

    @Test void restartRecoversAndAcknowledgementIsAtomicWithProjection() {
        service.publishAfterCommit(1, "ORDER_UPDATED", null, null, null);
        String id = jdbc.queryForObject("SELECT id FROM t_kds_projection_intent", String.class);
        fail = true;
        newService().processIntent(id);
        assertEquals(0, count("receipts"));
        assertEquals(1, count("t_kds_projection_intent"));
        assertEquals(1, jdbc.queryForObject("SELECT attempts FROM t_kds_projection_intent", Integer.class));
        fail = false;
        jdbc.update("UPDATE t_kds_projection_intent SET next_attempt_ms=0");
        newService().processIntent(id);
        newService().processIntent(id); // duplicate worker cannot repeat acknowledged work
        assertEquals(1, count("receipts"));
        assertEquals(0, count("t_kds_projection_intent"));
    }

    @Test void newerIntentCannotOvertakeFailedPredecessor() {
        service.publishAfterCommit(1, "ORDER_UPDATED", null, null, null);
        service.publishAfterCommit(1, "ORDER_CLOSED", null, null, null);
        java.util.List<String> ids = jdbc.queryForList("SELECT id FROM t_kds_projection_intent ORDER BY id", String.class);
        service.processIntent(ids.get(1));
        assertEquals(0, count("receipts"));
        service.processIntent(ids.get(0));
        jdbc.update("UPDATE t_kds_projection_intent SET next_attempt_ms=0");
        service.processIntent(ids.get(1));
        assertEquals(2, count("receipts"));
        assertEquals(0, count("t_kds_projection_intent"));
    }

    @Test void pollReadsOnlyBoundedBatchAndStopsOnRejection() {
        for (int i = 0; i < 80; i++) service.publishAfterCommit(i, "ORDER_UPDATED", null, null, null);
        clearInvocations(dispatcher);
        when(dispatcher.submit(anyInt(), any())).thenReturn(true);
        service.dispatchPendingIntents();
        verify(dispatcher, times(32)).submit(anyInt(), any());
        clearInvocations(dispatcher);
        when(dispatcher.submit(anyInt(), any())).thenReturn(false);
        service.dispatchPendingIntents();
        verify(dispatcher).submit(anyInt(), any());
        assertEquals(80, count("t_kds_projection_intent"));
    }

    @Test void insertFailureRollsBackBusinessEvenIfCallerCatchesIt() {
        jdbc.execute("DROP TABLE t_kds_projection_intent");
        assertThrows(org.springframework.transaction.UnexpectedRollbackException.class, () ->
            new TransactionTemplate(manager).execute(s -> {
                jdbc.update("INSERT INTO receipts VALUES (1)");
                try { service.publishAfterCommit(1, "ORDER_UPDATED", null, null, null); }
                catch (Exception ignored) { }
                return null;
            }));
        assertEquals(0, count("receipts"));
    }

    @Test void automaticAcceptanceAndIntentShareOneTransaction() {
        assertTrue(service.persistAcceptedOrder(1, () -> jdbc.update("INSERT INTO receipts VALUES (1)") == 1));
        assertEquals(1, count("receipts"));
        assertEquals(1, count("t_kds_projection_intent"));
        assertFalse(service.persistAcceptedOrder(2, () -> {
            jdbc.update("INSERT INTO receipts VALUES (2)"); return false;
        }));
        assertEquals(1, count("receipts"));
        jdbc.execute("DROP TABLE t_kds_projection_intent");
        assertThrows(Exception.class, () -> service.persistAcceptedOrder(3,
                () -> jdbc.update("INSERT INTO receipts VALUES (3)") == 1));
        assertEquals(1, count("receipts"));
    }

    @Test void freshDataSourceRecoversTaskFromDisk(@org.junit.jupiter.api.io.TempDir java.nio.file.Path dir) {
        jdbc.execute("SET DB_CLOSE_DELAY 0");
        String url = "jdbc:h2:file:" + dir.resolve("recovery").toAbsolutePath().toString().replace('\\', '/') + ";MODE=MySQL";
        DriverManagerDataSource first = new DriverManagerDataSource(url, "sa", "");
        jdbc = new JdbcTemplate(first);
        manager = new DataSourceTransactionManager(first);
        new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(
                new org.springframework.core.io.FileSystemResource("docs/db_migration_kds_projection_intent.sql")).execute(first);
        jdbc.execute("CREATE TABLE receipts(order_id INT)");
        newService().publishAfterCommit(9, "ORDER_UPDATED", null, null, null);
        // DriverManagerDataSource holds no pool: every connection is now closed and H2 is on disk.
        DriverManagerDataSource restarted = new DriverManagerDataSource(url, "sa", "");
        jdbc = new JdbcTemplate(restarted);
        manager = new DataSourceTransactionManager(restarted);
        newService().processIntent(jdbc.queryForObject("SELECT id FROM t_kds_projection_intent", String.class));
        assertEquals(1, count("receipts"));
        assertEquals(0, count("t_kds_projection_intent"));
    }

    @Test void concurrentConsumersCannotAcknowledgeSameTaskTwice() throws Exception {
        service.publishAfterCommit(7, "ORDER_UPDATED", null, null, null);
        String id = jdbc.queryForObject("SELECT id FROM t_kds_projection_intent", String.class);
        java.util.concurrent.ExecutorService workers = java.util.concurrent.Executors.newFixedThreadPool(2);
        java.util.concurrent.CountDownLatch start = new java.util.concurrent.CountDownLatch(1);
        Runnable attempt = () -> {
            try { start.await(); }
            catch (InterruptedException ex) { Thread.currentThread().interrupt(); throw new AssertionError(ex); }
            newService().processIntent(id);
        };
        try {
            java.util.concurrent.Future<?> one = workers.submit(attempt);
            java.util.concurrent.Future<?> two = workers.submit(attempt);
            start.countDown();
            one.get(3, java.util.concurrent.TimeUnit.SECONDS);
            two.get(3, java.util.concurrent.TimeUnit.SECONDS);
            assertEquals(1, count("receipts"));
            assertEquals(0, count("t_kds_projection_intent"));
        } finally { workers.shutdownNow(); }
    }

    @Test void closedEventIsRecordedBeforeCommitAndNotOnRollback() {
        try (org.springframework.context.annotation.AnnotationConfigApplicationContext context =
                     new org.springframework.context.annotation.AnnotationConfigApplicationContext()) {
            context.registerBean(org.springframework.transaction.event.TransactionalEventListenerFactory.class);
            context.registerBean(CashierKdsProjectionService.class, () -> service);
            context.getBeanFactory().registerSingleton("kdsPushService", mock(com.lanf.kds.service.KdsPushService.class));
            context.register(com.lanf.kds.event.KdsEventListener.class);
            context.refresh();
            new TransactionTemplate(manager).execute(s -> {
                context.publishEvent(new com.lanf.kds.event.KdsOrderStatusChangedEvent(this, 1, 1, "N1", 20, 40));
                s.setRollbackOnly(); return null;
            });
            assertEquals(0, count("t_kds_projection_intent"));
            new TransactionTemplate(manager).execute(s -> {
                context.publishEvent(new com.lanf.kds.event.KdsOrderStatusChangedEvent(this, 1, 1, "N1", 20, 40));
                return null;
            });
            assertEquals(1, count("t_kds_projection_intent"));
            assertEquals("ORDER_CLOSED", jdbc.queryForObject("SELECT event_type FROM t_kds_projection_intent", String.class));
        }
    }

    int count(String table) { return jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class); }
}
