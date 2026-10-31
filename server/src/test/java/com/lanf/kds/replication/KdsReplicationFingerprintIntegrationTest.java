package com.lanf.kds.replication;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.controller.OrderController;
import com.lanf.kds.service.KdsCashierAuthorityService;
import com.lanf.kds.service.KdsDishAvailabilityService;
import com.lanf.kds.service.KdsLackService;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabase;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;

class KdsReplicationFingerprintIntegrationTest {
    private final ObjectMapper mapper = new ObjectMapper();
    private EmbeddedDatabase database;
    private JdbcTemplate jdbc;
    private KdsReplicationService service;

    @BeforeEach
    void setup() {
        database = new EmbeddedDatabaseBuilder().setType(EmbeddedDatabaseType.H2)
                .setName("kds-fingerprint-" + System.nanoTime() + ";MODE=MySQL;DB_CLOSE_DELAY=-1").build();
        jdbc = new JdbcTemplate(database);
        jdbc.execute("CREATE TABLE t_kds_replication_event ("
                + "id BIGINT AUTO_INCREMENT PRIMARY KEY,event_id VARCHAR(128) NOT NULL,shop_id INT NOT NULL,"
                + "event_type VARCHAR(40) NOT NULL,aggregate_key VARCHAR(128) NOT NULL,occurred_at_ms BIGINT NOT NULL,"
                + "operation_id VARCHAR(128),local_revision BIGINT,payload_json CLOB NOT NULL,publisher_device_code VARCHAR(64),request_fingerprint CHAR(64),"
                + "status VARCHAR(20) NOT NULL,result_json CLOB,error_code INT,error_message VARCHAR(500),"
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
                + "applied_at TIMESTAMP,retry_count INT DEFAULT 0,dead_lettered_at TIMESTAMP,resolution_action VARCHAR(20),"
                + "resolution_reason VARCHAR(500),replacement_event_id VARCHAR(128),resolved_at TIMESTAMP,"
                + "CONSTRAINT uk_event UNIQUE(event_id),CONSTRAINT uk_operation UNIQUE(shop_id,operation_id))");
        jdbc.execute("CREATE TABLE t_kds_shop_authority ("
                + "shop_id INT PRIMARY KEY,authority_mode VARCHAR(16) NOT NULL,"
                + "protocol_version INT NOT NULL,updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.update("INSERT INTO t_kds_shop_authority "
                + "(shop_id,authority_mode,protocol_version) VALUES (7,'legacy',2)");
        service = new KdsReplicationService(jdbc, mapper, new DataSourceTransactionManager(database),
                mock(OrderController.class), mock(IDishService.class), mock(IOrderDetailService.class),
                mock(KdsDishAvailabilityService.class), mock(KdsCashierAuthorityService.class),
                mock(KdsReplicationAuditService.class), mock(KdsLackService.class));
    }

    @AfterEach
    void shutdown() {
        database.shutdown();
    }

    @Test
    void sameRequestIsStableDuplicateButDifferentPayloadCannotPolluteOriginal() throws Exception {
        KdsReplicationEventRequest original = request("event-1", "operation-1", 1);
        seedApplied(original);

        KdsReplicationOutcome duplicate = service.accept(7, original, authorizedRequest());
        KdsReplicationOutcome operationDuplicate = service.accept(
                7, request("event-other", "operation-1", 1), authorizedRequest());
        KdsReplicationOutcome conflict = service.accept(7, request("event-1", "operation-1", 2), authorizedRequest());
        KdsReplicationOutcome operationConflict = service.accept(
                7, request("event-other", "operation-1", 2), authorizedRequest());

        assertEquals(0, duplicate.getBusinessCode());
        assertEquals(true, duplicate.getData().get("duplicate"));
        assertEquals(0, operationDuplicate.getBusinessCode());
        assertEquals("event-1", operationDuplicate.getData().get("event_id"));
        assertEquals(4091, conflict.getBusinessCode());
        assertEquals(4091, operationConflict.getBusinessCode());
        assertTrue(conflict.getMessage().contains("different request"));
        assertEquals("applied", jdbc.queryForObject(
                "SELECT status FROM t_kds_replication_event WHERE event_id='event-1'", String.class));
        assertTrue(jdbc.queryForObject(
                "SELECT payload_json FROM t_kds_replication_event WHERE event_id='event-1'", String.class)
                .contains("\"quantity\":1"));
    }

    @Test
    void concurrentDuplicatesSerializeOnTheStoredFingerprint() throws Exception {
        KdsReplicationEventRequest original = request("event-2", "operation-2", 1);
        seedApplied(original);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        List<Callable<KdsReplicationOutcome>> tasks = new ArrayList<>();
        for (int i = 0; i < 2; i++) tasks.add(() -> {
            start.await();
            return service.accept(7, request("event-2", "operation-2", 1), authorizedRequest());
        });
        List<Future<KdsReplicationOutcome>> futures = new ArrayList<>();
        for (Callable<KdsReplicationOutcome> task : tasks) futures.add(executor.submit(task));
        start.countDown();
        for (Future<KdsReplicationOutcome> future : futures) {
            assertEquals(0, future.get().getBusinessCode());
        }
        executor.shutdownNow();
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_replication_event", Integer.class));
    }

    @Test
    void cloudAuthorityRejectsLegacyReplicationBeforeItCanCaptureState() throws Exception {
        jdbc.update("UPDATE t_kds_shop_authority SET authority_mode='cloud' WHERE shop_id=7");

        KdsReplicationOutcome outcome = service.accept(
                7, request("event-cloud-blocked", "operation-cloud-blocked", 1),
                authorizedRequest());

        assertEquals(4091, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("cloud-authoritative"));
        assertEquals(0, jdbc.queryForObject(
                "SELECT COUNT(*) FROM t_kds_replication_event", Integer.class));
    }

    @Test
    void missingAuthorityConfigurationRejectsLegacyReplicationFailClosed() throws Exception {
        jdbc.update("DELETE FROM t_kds_shop_authority WHERE shop_id=7");

        KdsReplicationOutcome outcome = service.accept(
                7, request("event-unconfigured-blocked", "operation-unconfigured-blocked", 1),
                authorizedRequest());

        assertEquals(4091, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("cloud-authoritative"));
        assertEquals(0, jdbc.queryForObject(
                "SELECT COUNT(*) FROM t_kds_replication_event", Integer.class));
    }

    @Test
    void cloudAuthorityRejectsLegacyDeadLetterRetryWithoutChangingTheEvent() throws Exception {
        jdbc.update("UPDATE t_kds_shop_authority SET authority_mode='cloud' WHERE shop_id=7");
        KdsReplicationEventRequest deadLetter = request(
                "event-cloud-dead-letter", "operation-cloud-dead-letter", 1);
        String payload = mapper.writeValueAsString(deadLetter.getPayload());
        jdbc.update("INSERT INTO t_kds_replication_event "
                        + "(event_id,shop_id,event_type,aggregate_key,occurred_at_ms,operation_id,payload_json,"
                        + "publisher_device_code,request_fingerprint,status,retry_count) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,'dead_letter',0)",
                deadLetter.getEventId(), 7, deadLetter.getEventType(), deadLetter.getAggregateKey(),
                deadLetter.getOccurredAtMs(), deadLetter.getPayload().get("operation_id").asText(), payload,
                "cashier-primary", KdsReplicationFingerprint.compute(mapper, 7, deadLetter.getEventType(),
                        deadLetter.getAggregateKey(), deadLetter.getOccurredAtMs(), "cashier-primary",
                        deadLetter.getPayload()));

        KdsReplicationOutcome outcome = service.retryDeadLetter(
                7, deadLetter.getEventId(), authorizedRequest());

        assertEquals(4091, outcome.getBusinessCode());
        assertTrue(outcome.getMessage().contains("cloud-authoritative"));
        assertEquals("dead_letter", jdbc.queryForObject(
                "SELECT status FROM t_kds_replication_event WHERE event_id=?", String.class,
                deadLetter.getEventId()));
        assertEquals(0, jdbc.queryForObject(
                "SELECT retry_count FROM t_kds_replication_event WHERE event_id=?", Integer.class,
                deadLetter.getEventId()));
    }

    private void seedApplied(KdsReplicationEventRequest request) throws Exception {
        String payload = mapper.writeValueAsString(request.getPayload());
        String fingerprint = KdsReplicationFingerprint.compute(mapper, 7, request.getEventType(),
                request.getAggregateKey(), request.getOccurredAtMs(), "cashier-primary", request.getPayload());
        jdbc.update("INSERT INTO t_kds_replication_event "
                        + "(event_id,shop_id,event_type,aggregate_key,occurred_at_ms,operation_id,payload_json,"
                        + "publisher_device_code,request_fingerprint,status,result_json) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                request.getEventId(), 7, request.getEventType(), request.getAggregateKey(), request.getOccurredAtMs(),
                request.getPayload().get("operation_id").asText(), payload, "cashier-primary", fingerprint, "applied",
                "{\"event_id\":\"" + request.getEventId() + "\",\"accepted\":true,\"duplicate\":false}");
    }

    private KdsReplicationEventRequest request(String eventId, String operationId, int quantity) throws Exception {
        return mapper.readValue("{\"event_id\":\"" + eventId + "\",\"event_type\":\"order_created\","
                + "\"aggregate_key\":\"order:37\",\"occurred_at_ms\":10,\"payload\":{\"shop_id\":7,"
                + "\"local_order_id\":37,\"operation_id\":\"" + operationId + "\","
                + "\"fulfillment_type\":\"dine_in\",\"created_at_ms\":10,\"lines\":[{"
                + "\"local_detail_id\":1,\"dish_id\":2,\"quantity\":" + quantity + "}]}}",
                KdsReplicationEventRequest.class);
    }

    private MockHttpServletRequest authorizedRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(KdsReplicationService.CASHIER_DEVICE_HEADER, "cashier-primary");
        return request;
    }
}
