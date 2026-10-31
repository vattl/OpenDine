package com.lanf.kds.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.service.KdsCashierAuthorityService;
import com.lanf.realtime.CashierEventWebSocketHub;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabase;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

class CashierKdsDeliveryServiceTest {
    private EmbeddedDatabase database;
    private JdbcTemplate jdbc;
    private CashierKdsLeaseService leaseService;
    private CashierKdsProjectionService projectionService;
    private CashierKdsDeliveryService deliveryService;
    private ObjectMapper objectMapper;
    private CashierKdsBootstrapRepair bootstrapRepair;

    @BeforeEach
    void setUp() {
        database = new EmbeddedDatabaseBuilder().setType(EmbeddedDatabaseType.H2)
                .setName("cashier-kds-delivery-" + System.nanoTime() + ";MODE=MySQL").build();
        jdbc = new JdbcTemplate(database);
        objectMapper = new ObjectMapper();

        jdbc.execute("CREATE TABLE t_kds_authority_config_version (shop_id INT PRIMARY KEY, cashier_device_code VARCHAR(64), version BIGINT, snapshot_hash VARCHAR(64))");
        jdbc.execute("CREATE TABLE t_kds_delivery_consumer (shop_id INT PRIMARY KEY, device_code VARCHAR(64), authority_epoch BIGINT DEFAULT 0, lease_token_hash VARCHAR(64), lease_until TIMESTAMP, ack_cursor BIGINT DEFAULT 0, last_delivered_cursor BIGINT DEFAULT 0, bootstrap_base_cursor BIGINT DEFAULT 0, bootstrap_required TINYINT DEFAULT 1, client_version VARCHAR(64), last_seen_at TIMESTAMP, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE t_kds_delivery_event (id BIGINT AUTO_INCREMENT PRIMARY KEY, event_id VARCHAR(64) UNIQUE, shop_id INT, order_id INT, projection_version BIGINT, event_type VARCHAR(32), origin_channel VARCHAR(24), origin_device_code VARCHAR(64), changed_detail_ids_json TEXT, payload_json LONGTEXT, occurred_at_ms BIGINT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE (order_id, projection_version))");
        jdbc.execute("CREATE TABLE t_kds_order_projection (order_id INT PRIMARY KEY, shop_id INT, projection_version BIGINT, state VARCHAR(16), source_channel VARCHAR(24), payload_json LONGTEXT, payload_hash VARCHAR(64), last_event_cursor BIGINT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE t_order (id INT AUTO_INCREMENT PRIMARY KEY, order_no VARCHAR(64) UNIQUE, shop_id INT, table_number VARCHAR(32), number_of_diners INT, remark VARCHAR(255), openid VARCHAR(64), merchantId VARCHAR(64), dineInOrTakeOut VARCHAR(32), order_receiving VARCHAR(32), transac_status VARCHAR(32), order_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE t_order_detail (id INT AUTO_INCREMENT PRIMARY KEY, mId INT, dish_id INT, name VARCHAR(64), selectedSpicy VARCHAR(64), unit VARCHAR(32), quantity VARCHAR(32), refunded_quantity INT DEFAULT 0, line_status VARCHAR(32), line_type VARCHAR(32), client_line_id VARCHAR(64), combo_id BIGINT, combo_instance_id VARCHAR(64), parent_detail_id BIGINT, cid VARCHAR(64), remark VARCHAR(255))");
        jdbc.execute("CREATE TABLE t_kds_ticket (shop_id INT, order_id INT, detail_id INT, "
                + "item_status INT, prep_quantity INT DEFAULT 0, cooked_quantity INT DEFAULT 0, "
                + "served_quantity INT DEFAULT 0)");

        jdbc.update("INSERT INTO t_kds_authority_config_version(shop_id,cashier_device_code,version) VALUES (1,'POS-01',1)");
        jdbc.execute("ALTER TABLE t_order ADD off_time TIMESTAMP");
        jdbc.execute("CREATE TABLE t_kds_replication_line_state (shop_id INT, cloud_order_id INT, cloud_detail_id INT, workflow_queue VARCHAR(32), prep_remaining INT, cook_remaining INT, ready_remaining INT, local_revision BIGINT)");

        leaseService = new CashierKdsLeaseService(jdbc, new KdsCashierAuthorityService(jdbc));
        CashierEventWebSocketHub hub = mock(CashierEventWebSocketHub.class);
        DataSourceTransactionManager txManager = new DataSourceTransactionManager(database);
        projectionService = new CashierKdsProjectionService(
                jdbc, objectMapper, hub, txManager,
                new CashierKdsProjectionPublishRetry(org.mockito.Mockito.mock(org.springframework.scheduling.TaskScheduler.class)));
        bootstrapRepair = org.mockito.Mockito.spy(new CashierKdsBootstrapRepair(jdbc,projectionService,txManager));
        org.mockito.Mockito.doNothing().when(bootstrapRepair).requestRepair(org.mockito.ArgumentMatchers.anyInt());
        deliveryService = new CashierKdsDeliveryService(jdbc, objectMapper, leaseService, projectionService,bootstrapRepair);
    }

    @AfterEach
    void tearDown() {
        bootstrapRepair.close();
        database.shutdown();
    }

    @Test
    void repairWakeupsAreBoundedAndNeverRunOnRequestThread() throws Exception {
        jdbc.update("INSERT INTO t_order(id,order_no,shop_id,order_receiving) VALUES(1,'ASYNC-1',1,'rec_order')");
        CashierKdsProjectionService blocked=org.mockito.Mockito.mock(CashierKdsProjectionService.class);
        java.util.concurrent.CountDownLatch entered=new java.util.concurrent.CountDownLatch(1), release=new java.util.concurrent.CountDownLatch(1);
        Thread request=Thread.currentThread();
        org.mockito.Mockito.when(blocked.publish(org.mockito.ArgumentMatchers.anyInt(),org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.isNull(),org.mockito.ArgumentMatchers.isNull(),org.mockito.ArgumentMatchers.isNull())).thenAnswer(call -> {
            assertNotEquals(request,Thread.currentThread()); entered.countDown();
            release.await(5,java.util.concurrent.TimeUnit.SECONDS); return null;
        });
        CashierKdsBootstrapRepair repair=new CashierKdsBootstrapRepair(jdbc,blocked,new DataSourceTransactionManager(database));
        try {
            repair.requestRepair(1); assertTrue(entered.await(2,java.util.concurrent.TimeUnit.SECONDS));
            repair.requestRepair(1);
            for (int shop=2;shop<=18;shop++) repair.requestRepair(shop);
            java.util.concurrent.ThreadPoolExecutor executor=(java.util.concurrent.ThreadPoolExecutor)
                    org.springframework.test.util.ReflectionTestUtils.getField(repair,"worker");
            assertEquals(16,executor.getQueue().size());
            assertEquals(17,((java.util.Set<?>)org.springframework.test.util.ReflectionTestUtils.getField(repair,"scheduled")).size());
            assertThrows(CashierKdsDeliveryException.class,()->repair.ensureReady(1));
        } finally { release.countDown(); repair.close();
            ((java.util.concurrent.ExecutorService)org.springframework.test.util.ReflectionTestUtils.getField(repair,"worker")).awaitTermination(2,java.util.concurrent.TimeUnit.SECONDS); }
    }
    @Test
    void repairBatchIsBoundedAndPartialPagesCannotClearBootstrapGate() {
        for (int i=1;i<=35;i++) jdbc.update("INSERT INTO t_order(id,order_no,shop_id,order_receiving) VALUES(?,?,1,'rec_order')",i,"BATCH-"+i);
        bootstrapRepair.repairBatch(1);
        assertEquals(32,jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_order_projection",Integer.class));
        Map<String,Object> lease=leaseService.lease(1,"POS-01",java.util.Collections.singletonMap("action","ACQUIRE"));
        long epoch=((Number)lease.get("authorityEpoch")).longValue(); String token=(String)lease.get("leaseToken");
        assertThrows(CashierKdsDeliveryException.class,()->deliveryService.bootstrap(1,"POS-01",epoch,token,null,20));
        deliveryService.ack(1,"POS-01",epoch,token,0);
        assertTrue(leaseService.validate(1,"POS-01",epoch,token).bootstrapRequired);
        bootstrapRepair.repairBatch(1);
        Map<String,Object> first=deliveryService.bootstrap(1,"POS-01",epoch,token,null,20);
        assertEquals(false,first.get("complete"));
        deliveryService.ack(1,"POS-01",epoch,token,0);
        assertTrue(leaseService.validate(1,"POS-01",epoch,token).bootstrapRequired);
        Map<String,Object> renew=new LinkedHashMap<>(); renew.put("action","RENEW"); renew.put("authorityEpoch",epoch); renew.put("leaseToken",token);
        assertEquals(epoch,leaseService.lease(1,"POS-01",renew).get("authorityEpoch"));
        Map<String,Object> last=deliveryService.bootstrap(1,"POS-01",epoch,token,(String)first.get("nextPageToken"),20);
        assertEquals(true,last.get("complete"));
        deliveryService.ack(1,"POS-01",epoch,token,((Number)last.get("baseCursor")).longValue());
        assertFalse(leaseService.validate(1,"POS-01",epoch,token).bootstrapRequired);
    }

    @Test
    void pageReadRunsWithoutLeaseTransactionAndRechecksEpochBeforeReturning() {
        Map<String,Object> lease=leaseService.lease(1,"POS-01",java.util.Collections.singletonMap("action","ACQUIRE"));
        long epoch=((Number)lease.get("authorityEpoch")).longValue(); String token=(String)lease.get("leaseToken");
        JdbcTemplate observed=org.mockito.Mockito.spy(jdbc);
        org.mockito.Mockito.doAnswer(call -> {
            assertFalse(org.springframework.transaction.support.TransactionSynchronizationManager.isActualTransactionActive());
            Map<String,Object> renew=new LinkedHashMap<>(); renew.put("action","RENEW"); renew.put("authorityEpoch",epoch); renew.put("leaseToken",token);
            java.util.concurrent.ExecutorService renewer=java.util.concurrent.Executors.newSingleThreadExecutor();
            try { renewer.submit(()->new org.springframework.transaction.support.TransactionTemplate(new DataSourceTransactionManager(database))
                    .execute(status -> leaseService.lease(1,"POS-01",renew))).get(2,java.util.concurrent.TimeUnit.SECONDS); }
            finally { renewer.shutdownNow(); }
            jdbc.update("UPDATE t_kds_delivery_consumer SET authority_epoch=authority_epoch+1 WHERE shop_id=1");
            return java.util.Collections.emptyList();
        }).when(observed).queryForList(org.mockito.ArgumentMatchers.startsWith("SELECT order_id,payload_json"),
                org.mockito.ArgumentMatchers.<Object[]>any());
        org.springframework.aop.framework.ProxyFactory leaseFactory=new org.springframework.aop.framework.ProxyFactory(leaseService);
        leaseFactory.setProxyTargetClass(true);
        leaseFactory.addAdvice(new org.springframework.transaction.interceptor.TransactionInterceptor(new DataSourceTransactionManager(database),
                new org.springframework.transaction.annotation.AnnotationTransactionAttributeSource()));
        CashierKdsLeaseService fencedLease=(CashierKdsLeaseService)leaseFactory.getProxy();
        CashierKdsDeliveryService target=new CashierKdsDeliveryService(observed,objectMapper,fencedLease,projectionService,bootstrapRepair);
        org.springframework.aop.framework.ProxyFactory factory=new org.springframework.aop.framework.ProxyFactory(target);
        factory.setProxyTargetClass(true);
        factory.addAdvice(new org.springframework.transaction.interceptor.TransactionInterceptor(new DataSourceTransactionManager(database),
                new org.springframework.transaction.annotation.AnnotationTransactionAttributeSource()));
        CashierKdsDeliveryService proxy=(CashierKdsDeliveryService)factory.getProxy();
        CashierKdsDeliveryException error=assertThrows(CashierKdsDeliveryException.class,()->proxy.bootstrap(1,"POS-01",epoch,token,null,100));
        assertEquals(409,error.getHttpStatus());
        assertEquals(0,jdbc.queryForObject("SELECT last_delivered_cursor FROM t_kds_delivery_consumer WHERE shop_id=1",Integer.class));
    }
    @Test
    void durableIntentWaitsForAcceptanceThenPersistsEventAndAcknowledges() {
        org.springframework.jdbc.datasource.init.ResourceDatabasePopulator migration =
                new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(
                        new org.springframework.core.io.FileSystemResource("docs/db_migration_kds_projection_intent.sql"));
        migration.execute(database);
        jdbc.update("INSERT INTO t_order(id,order_no,shop_id,order_receiving) VALUES (99,'WAIT-99',1,'mis_order')");
        jdbc.update("INSERT INTO t_kds_projection_intent(order_id,event_type) VALUES (99,'ORDER_UPDATED')");
        String id = jdbc.queryForObject("SELECT id FROM t_kds_projection_intent", String.class);
        projectionService.processIntent(id);
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_projection_intent", Integer.class));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_delivery_event", Integer.class));
        jdbc.update("UPDATE t_order SET order_receiving='rec_order' WHERE id=99");
        jdbc.update("UPDATE t_kds_projection_intent SET next_attempt_ms=0");
        projectionService.processIntent(id);
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_projection_intent", Integer.class));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_delivery_event", Integer.class));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_order_projection", Integer.class));
        jdbc.update("INSERT INTO t_kds_projection_intent(order_id,event_type) VALUES (99,'ORDER_UPDATED')");
        projectionService.processIntent(jdbc.queryForObject("SELECT id FROM t_kds_projection_intent", String.class));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_delivery_event", Integer.class));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_projection_intent", Integer.class));
    }

    @Test
    void lease_acquireAndRenewWorkflow() {
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        req.put("clientVersion", "flutter-cashier");

        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        assertNotNull(lease);
        assertEquals(1L, ((Number) lease.get("authorityEpoch")).longValue());
        String token = (String) lease.get("leaseToken");
        assertNotNull(token);
        assertTrue(token.length() >= 32);

        Map<String, Object> renew = new LinkedHashMap<>();
        renew.put("action", "RENEW");
        renew.put("authorityEpoch", 1L);
        renew.put("leaseToken", token);

        Map<String, Object> renewed = leaseService.lease(1, "POS-01", renew);
        assertEquals(1L, ((Number) renewed.get("authorityEpoch")).longValue());
        assertEquals(token, renewed.get("leaseToken"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void historyBackfillIncludesCompletedAndUnacceptedOrdersWithoutPublishingEvents() {
        jdbc.execute("CREATE TABLE t_shop (id INT PRIMARY KEY, open_time VARCHAR(16), close_time VARCHAR(16), settle_time VARCHAR(16))");
        jdbc.update("INSERT INTO t_shop (id,open_time,close_time) VALUES (1,'00:00','00:00')");
        jdbc.execute("CREATE TABLE t_kds_order (order_id INT PRIMARY KEY, shop_id INT, kds_order_status INT)");
        jdbc.update("INSERT INTO t_order(id,order_no,shop_id,order_receiving,transac_status,off_time) VALUES (1,'DONE',1,'off_order','settled',NOW()),(2,'WAIT',1,'mis_order','unsettled',NULL),(3,'OTHER',2,'off_order','settled',NOW())");
        jdbc.update("INSERT INTO t_order(id,order_no,shop_id,order_receiving,order_time) VALUES (4,'OLD',1,'off_order',TIMESTAMP '2020-01-01 00:00:00')");
        jdbc.update("INSERT INTO t_kds_order VALUES (1,1,40)");
        jdbc.update("INSERT INTO t_order_detail(id,mId,dish_id,name,quantity) VALUES (11,1,1,'羊肉串','10'),(12,2,1,'牛肉串','3')");
        jdbc.update("INSERT INTO t_kds_ticket "
                + "(shop_id,order_id,detail_id,item_status,prep_quantity,cooked_quantity,served_quantity) "
                + "VALUES (1,2,12,10,3,3,1)");
        Map<String,Object> lease = leaseService.lease(1,"POS-01",java.util.Collections.singletonMap("action","ACQUIRE"));
        long epoch = ((Number)lease.get("authorityEpoch")).longValue();
        String token = (String)lease.get("leaseToken");
        Map<String,Object> page = deliveryService.businessDayOrderDetails(1,"POS-01",epoch,token,null,1);
        Map<String,Object> order = ((List<Map<String,Object>>)page.get("orders")).get(0);
        assertEquals(true,order.get("completed"));
        assertNotNull(order.get("completedAtMs"));
        assertEquals(false,order.get("archived"));
        assertEquals("completed",order.get("orderStatus"));
        Map<String,Object> detail = ((List<Map<String,Object>>)order.get("details")).get(0);
        assertEquals("done",detail.get("workflowQueue"));
        assertEquals(1,detail.get("doneLine"));
        assertEquals(10,detail.get("lineQuantity"));
        assertEquals(0,detail.get("readyRemaining"));
        Map<String,Object> next = deliveryService.businessDayOrderDetails(1,"POS-01",epoch,token,(String)page.get("nextCursor"),1);
        assertEquals(true,next.get("complete"));
        Map<String,Object> waiting = ((List<Map<String,Object>>)next.get("orders")).get(0);
        assertEquals(2,waiting.get("orderId"));
        assertEquals(false,waiting.get("completed"));
        Map<String,Object> partial = ((List<Map<String,Object>>)waiting.get("details")).get(0);
        assertEquals("ready_serve", partial.get("workflowQueue"));
        assertEquals(2, partial.get("readyRemaining"));
        assertEquals(0, partial.get("doneLine"));
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_delivery_event",Integer.class));
        assertThrows(CashierKdsDeliveryException.class, () -> deliveryService.businessDayOrderDetails(1,"POS-01",epoch,"bad-token",null,1));
    }

    @Test
    void bootstrap_reconcilesActiveOrdersAndReturnsSnapshot() {
        // Prepare lease
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        long epoch = ((Number) lease.get("authorityEpoch")).longValue();
        String token = (String) lease.get("leaseToken");

        // Insert active order in t_order that has not yet been projected
        jdbc.update("INSERT INTO t_order (id, order_no, shop_id, table_number, number_of_diners, remark, openid, dineInOrTakeOut, order_receiving, transac_status, order_time) "
                + "VALUES (9001, 'ORD20260817001', 1, '28', 4, '少放辣', 'cashier_system', '堂食', 'rec_order', 'unsettled', NOW())");
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8801, 9001, 101, '油边王', '微辣', '串', '2', 0, 'normal')");
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8802, 9001, 102, '吊龙牛肉', '微辣', '串', '1', 0, 'normal')");

        // Missing projections must not be silently declared complete.
        CashierKdsDeliveryException pending = assertThrows(CashierKdsDeliveryException.class,
                () -> deliveryService.bootstrap(1, "POS-01", epoch, token, null, 100));
        assertEquals(503,pending.getHttpStatus());
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_order_projection",Integer.class));
        bootstrapRepair.repairBatch(1);
        // Fetch bootstrap
        Map<String, Object> bootstrap = deliveryService.bootstrap(1, "POS-01", epoch, token, null, 100);
        assertNotNull(bootstrap);
        assertTrue(((Number) bootstrap.get("baseCursor")).longValue() > 0);
        assertTrue((Boolean) bootstrap.get("complete"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> orders = (List<Map<String, Object>>) bootstrap.get("orders");
        assertNotNull(orders);
        assertEquals(1, orders.size());

        Map<String, Object> order = orders.get(0);
        assertEquals(9001, ((Number) order.get("orderId")).intValue());
        assertEquals("ORD20260817001", order.get("orderNo"));
        assertEquals("28", order.get("tableNumber"));
        assertEquals("DINE_IN", order.get("fulfillmentType"));
        assertEquals("READY", order.get("state"));
        assertEquals("POS", order.get("sourceChannel"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> lines = (List<Map<String, Object>>) order.get("lines");
        assertEquals(2, lines.size());
        assertEquals(101, ((Number) lines.get(0).get("dishId")).intValue());
        assertEquals("油边王", lines.get(0).get("dishName"));
        assertEquals(2, ((Number) lines.get(0).get("quantity")).intValue());
        assertEquals(2, ((Number) lines.get(0).get("remainingQuantity")).intValue());
        assertEquals(0, ((Number) lines.get(0).get("refundedQuantity")).intValue());
    }

    @Test
    void bootstrap_doesNotProjectUnacceptedCashierOrder() {
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        long epoch = ((Number) lease.get("authorityEpoch")).longValue();
        String token = (String) lease.get("leaseToken");

        // Insert cashier quick order with order_receiving = 'mis_order'
        jdbc.update("INSERT INTO t_order (id, order_no, shop_id, table_number, number_of_diners, remark, openid, dineInOrTakeOut, order_receiving, transac_status, order_time) "
                + "VALUES (9002, 'ORD20260817002', 1, '26', 2, '', 'cashier_system', '堂食', 'mis_order', 'unsettled', NOW())");
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8803, 9002, 103, '精品牛肉串', '微辣', '串', '5', 0, 'normal')");

        Map<String, Object> bootstrap = deliveryService.bootstrap(1, "POS-01", epoch, token, null, 100);
        assertNotNull(bootstrap);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> orders = (List<Map<String, Object>>) bootstrap.get("orders");
        assertNotNull(orders);
        assertTrue(orders.isEmpty());
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_order_projection WHERE order_id=9002", Integer.class).intValue());
    }

    @Test
    void eventsAndAck_streamWorkflow() {
        // Lease
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        long epoch = ((Number) lease.get("authorityEpoch")).longValue();
        String token = (String) lease.get("leaseToken");

        // Bootstrap to clear bootstrap_required flag
        jdbc.update("INSERT INTO t_order (id, order_no, shop_id, table_number, number_of_diners, remark, openid, dineInOrTakeOut, order_receiving, transac_status, order_time) "
                + "VALUES (9001, 'ORD20260817001', 1, '28', 2, '', 'cashier_system', '堂食', 'rec_order', 'unsettled', NOW())");
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8801, 9001, 101, '油边王', '不辣', '份', '1', 0, 'normal')");

        bootstrapRepair.repairBatch(1);
        Map<String, Object> boot = deliveryService.bootstrap(1, "POS-01", epoch, token, null, 100);
        long baseCursor = ((Number) boot.get("baseCursor")).longValue();

        // Ack bootstrap
        deliveryService.ack(1, "POS-01", epoch, token, baseCursor);

        // Add dishes to order -> trigger publish
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8802, 9001, 102, '烤肉', '微辣', '份', '2', 0, 'normal')");
        Long newCursor = projectionService.publish(9001, "ORDER_UPDATED", "POS", "POS-01", java.util.Collections.singletonList(8802));
        assertNotNull(newCursor);
        assertTrue(newCursor > baseCursor);

        // Fetch events after baseCursor
        Map<String, Object> eventsResult = deliveryService.events(1, "POS-01", epoch, token, baseCursor, 200);
        assertNotNull(eventsResult);
        assertFalse((Boolean) eventsResult.get("snapshotRequired"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> events = (List<Map<String, Object>>) eventsResult.get("events");
        assertEquals(1, events.size());
        Map<String, Object> evt = events.get(0);
        assertEquals("ORDER_UPDATED", evt.get("eventType"));
        assertEquals(newCursor, ((Number) evt.get("cursor")).longValue());

        // Ack event
        Map<String, Object> ackResult = deliveryService.ack(1, "POS-01", epoch, token, newCursor);
        assertEquals(newCursor, ((Number) ackResult.get("acknowledgedCursor")).longValue());
        assertEquals(0L, ((Number) ackResult.get("lag")).longValue());
    }

    @Test
    void status_reportsCorrectLagAndOnlineState() {
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        long epoch = ((Number) lease.get("authorityEpoch")).longValue();
        String token = (String) lease.get("leaseToken");

        Map<String, Object> status = deliveryService.status(1);
        assertNotNull(status);
        assertEquals(1, ((Number) status.get("shopId")).intValue());
        assertEquals("POS-01", status.get("deviceCode"));
        assertTrue((Boolean) status.get("authorityOnline"));
    }

    @Test
    void orderCancelledOrDeleted_emitsCancelEventAndExcludedFromBootstrap() {
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        long epoch = ((Number) lease.get("authorityEpoch")).longValue();
        String token = (String) lease.get("leaseToken");

        // 1. Create order and publish READY projection
        jdbc.update("INSERT INTO t_order (id, order_no, shop_id, table_number, number_of_diners, remark, openid, dineInOrTakeOut, order_receiving, transac_status, order_time) "
                + "VALUES (9005, 'ORD20260818005', 1, '10', 2, '', 'cashier_system', '堂食', 'rec_order', 'unsettled', NOW())");
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8805, 9005, 105, '烤五花肉', '微辣', '串', '3', 0, 'normal')");

        Long initialCursor = projectionService.publish(9005, "ORDER_ACCEPTED", "POS", "POS-01", null);
        assertNotNull(initialCursor);

        // Bootstrap and ack initial order
        Map<String, Object> initialBootstrap = deliveryService.bootstrap(1, "POS-01", epoch, token, null, 100);
        assertNotNull(initialBootstrap);
        deliveryService.ack(1, "POS-01", epoch, token, initialCursor);

        // 2. Simulate order deletion (rows removed from t_order and t_order_detail) and cancel publish
        jdbc.update("DELETE FROM t_order WHERE id=9005");
        jdbc.update("DELETE FROM t_order_detail WHERE mId=9005");

        Long cancelCursor = projectionService.publish(9005, "ORDER_CANCELLED", "POS", "POS-01", null);
        assertNotNull(cancelCursor);
        assertTrue(cancelCursor > initialCursor);

        // 3. Events stream contains ORDER_CANCELLED event with VOIDED state
        Map<String, Object> eventsResult = deliveryService.events(1, "POS-01", epoch, token, initialCursor, 200);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> events = (List<Map<String, Object>>) eventsResult.get("events");
        assertEquals(1, events.size());
        Map<String, Object> evt = events.get(0);
        assertEquals("ORDER_CANCELLED", evt.get("eventType"));
        @SuppressWarnings("unchecked")
        Map<String, Object> proj = (Map<String, Object>) evt.get("projection");
        assertEquals("VOIDED", proj.get("state"));

        // 4. Bootstrap does NOT return the cancelled/deleted order
        Map<String, Object> bootstrap = deliveryService.bootstrap(1, "POS-01", epoch, token, null, 100);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> bootstrapOrders = (List<Map<String, Object>>) bootstrap.get("orders");
        assertTrue(bootstrapOrders.isEmpty());
    }

    /**
     * 回归：businessDayOrders（GET /cashier/kds/delivery/business-day/orders）在有效租约下返回营业日窗口订单。
     * 注：readOnly 事务与 SELECT ... FOR UPDATE 的矛盾只在 Spring 代理 + 真实 MySQL 下触发（本测试直接调用、无代理），
     * 此处守护该方法正常行为与结果契约，防止后续改动破坏快照语义。
     */
    @Test
    void businessDayOrders_returnsWindowOrdersWithKdsStatus() {
        jdbc.execute("CREATE TABLE IF NOT EXISTS t_shop (id INT PRIMARY KEY, open_time VARCHAR(16), close_time VARCHAR(16), settle_time VARCHAR(16))");
        jdbc.execute("CREATE TABLE IF NOT EXISTS t_kds_order (order_id INT PRIMARY KEY, shop_id INT, kds_order_status VARCHAR(32))");
        // 全天窗口，保证 NOW() 订单必落在当前营业日窗口内
        jdbc.update("INSERT INTO t_shop (id, open_time, close_time) VALUES (1, '00:00', '23:59')");

        Map<String, Object> req = new LinkedHashMap<>();
        req.put("action", "ACQUIRE");
        Map<String, Object> lease = leaseService.lease(1, "POS-01", req);
        long epoch = ((Number) lease.get("authorityEpoch")).longValue();
        String token = (String) lease.get("leaseToken");

        jdbc.update("INSERT INTO t_order (id, order_no, shop_id, table_number, number_of_diners, remark, openid, dineInOrTakeOut, order_receiving, transac_status, order_time) "
                + "VALUES (9010, 'ORD20260904001', 1, '8', 2, '', 'cashier_system', '堂食', 'rec_order', 'settled', NOW())");
        jdbc.update("INSERT INTO t_order_detail (id, mId, dish_id, name, selectedSpicy, unit, quantity, refunded_quantity, line_status) "
                + "VALUES (8810, 9010, 201, '烤鸡翅', '微辣', '串', '4', 0, 'normal')");
        jdbc.update("INSERT INTO t_kds_order (order_id, shop_id, kds_order_status) VALUES (9010, 1, 'COOKING')");

        Map<String, Object> result = deliveryService.businessDayOrders(1, "POS-01", epoch, token, null, 200);
        assertNotNull(result);
        assertEquals(1, ((Number) result.get("shopId")).intValue());
        assertTrue(result.containsKey("businessDayStart"));
        assertTrue(result.containsKey("businessDayEnd"));
        assertTrue(Boolean.TRUE.equals(result.get("complete")));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> orders = (List<Map<String, Object>>) result.get("orders");
        assertEquals(1, orders.size());
        Map<String, Object> o = orders.get(0);
        assertEquals(9010, ((Number) o.get("orderId")).intValue());
        assertEquals("COOKING", o.get("kdsOrderStatus"));
        assertEquals("settled", o.get("orderStatus"));
        assertEquals("8", o.get("tableNumber"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> details = (List<Map<String, Object>>) o.get("details");
        assertEquals(1, details.size());
        assertEquals("烤鸡翅", details.get(0).get("dishName"));
        assertEquals("4", details.get(0).get("quantity"));
    }
}
