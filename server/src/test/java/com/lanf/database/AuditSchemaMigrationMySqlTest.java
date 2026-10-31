package com.lanf.database;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

/** Opt-in integration test: only a generated disposable schema on the local debug instance. */
@EnabledIfEnvironmentVariable(named="C007_MYSQL_PASSWORD", matches=".+")
class AuditSchemaMigrationMySqlTest {
    @Test void migrateLegacySchemaAndRerunWithoutLosingData() throws Exception {
        String schema = "c007_test_" + UUID.randomUUID().toString().replace("-", "");
        try (Connection connection = DriverManager.getConnection(
                "jdbc:mysql://127.0.0.1:3307/?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai",
                "root", System.getenv("C007_MYSQL_PASSWORD"))) {
            JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
            jdbc.execute("CREATE DATABASE " + schema);
            try {
                connection.setCatalog(schema);
                // First install, then simulate the historical index and completed debt state.
                AuditSchemaMigration.apply(connection);
                jdbc.execute("ALTER TABLE t_cashier_collection_intent ADD UNIQUE KEY uk_cashier_collection_order(shop_id,order_no)");
                jdbc.execute("ALTER TABLE t_cashier_collection_intent DROP INDEX uk_cashier_collection_order_channel");
                jdbc.update("INSERT INTO t_invite_reward_clawback(invite_record_id,inviter_user_id,order_no,outstanding_amount,status) VALUES(1,1,'completed',12.34,'COMPLETED'),(2,1,'pending',5.67,'PENDING')");
                jdbc.update("DELETE FROM t_app_schema_version WHERE version='V007'");
                AuditSchemaMigration.apply(connection);
                AuditSchemaMigration.apply(connection);
                new PaymentSchemaReadiness(jdbc).verify();
                assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_app_schema_version", Integer.class));
                assertEquals(0, jdbc.queryForObject("SELECT outstanding_amount FROM t_invite_reward_clawback WHERE order_no='completed'", java.math.BigDecimal.class).signum());
                assertEquals(new java.math.BigDecimal("5.67"), jdbc.queryForObject("SELECT outstanding_amount FROM t_invite_reward_clawback WHERE order_no='pending'", java.math.BigDecimal.class));
                assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND index_name='uk_cashier_collection_order'", Integer.class));
                assertEquals(3, jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND index_name='uk_cashier_collection_order_channel' AND non_unique=0", Integer.class));
                verifyPaymentMatching(jdbc, schema);
            } finally {
                jdbc.execute("DROP DATABASE " + schema);
            }
        }
    }

    private void verifyPaymentMatching(JdbcTemplate jdbc, String schema) throws Exception {
        org.springframework.jdbc.datasource.DriverManagerDataSource dataSource = new org.springframework.jdbc.datasource.DriverManagerDataSource(
                "jdbc:mysql://127.0.0.1:3307/" + schema + "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai",
                "root", System.getenv("C007_MYSQL_PASSWORD"));
        org.springframework.transaction.support.TransactionTemplate tx = new org.springframework.transaction.support.TransactionTemplate(
                new org.springframework.jdbc.datasource.DataSourceTransactionManager(dataSource));
        tx.setTimeout(15);
        com.lanf.payment.service.CashierCollectionIntentService intents = new com.lanf.payment.service.CashierCollectionIntentService(new JdbcTemplate(dataSource));
        jdbc.update("INSERT INTO t_cashier_collection_intent(shop_id,order_no,session_id,channel,amount_fen,expires_at) VALUES (1,'shop1','s1','wechat',100,DATE_ADD(NOW(),INTERVAL 180 SECOND)),(2,'shop2','s2','wechat',100,DATE_ADD(NOW(),INTERVAL 180 SECOND)),(3,'a','s3','wechat',200,DATE_ADD(NOW(),INTERVAL 180 SECOND)),(3,'b','s4','wechat',200,DATE_ADD(NOW(),INTERVAL 180 SECOND))");
        assertEquals("shop1",tx.execute(status -> intents.matchAndConfirmByWebhook(1,"wechat",100,new java.util.Date())).getOrderNo());
        assertEquals("PENDING",jdbc.queryForObject("SELECT status FROM t_cashier_collection_intent WHERE shop_id=2",String.class));
        assertThrows(com.lanf.payment.service.CashierCollectionIntentService.AmbiguousCollectionException.class,
                () -> tx.execute(status -> intents.matchAndConfirmByWebhook(3,"wechat",200,new java.util.Date())));
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM t_cashier_collection_intent WHERE shop_id=3 AND status='PENDING'",Integer.class));
        java.util.concurrent.ExecutorService workers=java.util.concurrent.Executors.newFixedThreadPool(2);
        java.util.concurrent.CountDownLatch start=new java.util.concurrent.CountDownLatch(1);
        try {
            java.util.concurrent.Callable<Boolean> match=() -> {
                if (!start.await(10,java.util.concurrent.TimeUnit.SECONDS)) throw new IllegalStateException("Test start timeout");
                return tx.execute(status -> intents.matchAndConfirmByWebhook(2,"wechat",100,new java.util.Date()) != null);
            };
            java.util.concurrent.Future<Boolean> first=workers.submit(match), second=workers.submit(match);
            start.countDown();
            int matches=(first.get(20,java.util.concurrent.TimeUnit.SECONDS)?1:0)+(second.get(20,java.util.concurrent.TimeUnit.SECONDS)?1:0);
            assertEquals(1,matches,"Two concurrent transactions must not both claim the same intent");
        } finally { workers.shutdownNow(); workers.awaitTermination(20,java.util.concurrent.TimeUnit.SECONDS); }
    }
}

