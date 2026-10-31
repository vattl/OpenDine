package com.lanf.kds.replication;

import com.lanf.interceptor.SysInterceptor;
import com.lanf.kds.service.KdsCashierAuthorityService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.junit.jupiter.SpringExtension;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.support.TransactionTemplate;

import javax.annotation.Resource;
import javax.sql.DataSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

@ExtendWith(SpringExtension.class)
@ContextConfiguration(classes = KdsReplicationAuditTransactionTest.Config.class)
class KdsReplicationAuditTransactionTest {
    @Resource private JdbcTemplate jdbc;
    @Resource private PlatformTransactionManager transactionManager;
    @Resource private KdsReplicationAuditService auditService;
    @Resource private KdsCashierAuthorityService authorityService;

    @BeforeEach
    void schema() {
        jdbc.execute("CREATE TABLE IF NOT EXISTS t_kds_replication_dead_letter_audit ("
                + "id BIGINT AUTO_INCREMENT PRIMARY KEY,shop_id INT,event_id VARCHAR(128),action VARCHAR(40),"
                + "reason VARCHAR(500),replacement_event_id VARCHAR(128),operator_admin_id INT,"
                + "operator_subject VARCHAR(128),trace_id VARCHAR(128))");
        jdbc.update("DELETE FROM t_kds_replication_dead_letter_audit");
        jdbc.execute("CREATE TABLE IF NOT EXISTS t_kds_authority_config_version ("
                + "shop_id INT PRIMARY KEY,version BIGINT NOT NULL,cashier_device_code VARCHAR(64),"
                + "snapshot_hash VARCHAR(64),updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.update("DELETE FROM t_kds_authority_config_version");
    }

    @Test
    void cashierAuthoritySqlFencesByShopAndIndependentDeviceIdentity() {
        authorityService.configure(7, "cashier-primary");

        authorityService.requirePrimaryPublisher(7, "cashier-primary");
        assertThrows(KdsReplicationException.class,
                () -> authorityService.requirePrimaryPublisher(7, "kds-screen-device"));
        assertThrows(KdsReplicationException.class,
                () -> authorityService.requirePrimaryPublisher(8, "cashier-primary"));
        assertEquals("cashier-primary", jdbc.queryForObject(
                "SELECT cashier_device_code FROM t_kds_authority_config_version WHERE shop_id=7", String.class));
    }

    @Test
    void retryAuditCommitsEvenWhenOwningBusinessTransactionRollsBack() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 19);
        request.setAttribute(SysInterceptor.ATTR_TRACE_ID, "trace-retry-1");

        assertThrows(IllegalStateException.class, () -> new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> {
                    auditService.record(7, "event-1", "retry_requested", null, null, request);
                    throw new IllegalStateException("simulated business rollback");
                }));

        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_replication_dead_letter_audit", Integer.class));
        assertEquals("admin:19", jdbc.queryForObject(
                "SELECT operator_subject FROM t_kds_replication_dead_letter_audit", String.class));
        assertEquals("trace-retry-1", jdbc.queryForObject(
                "SELECT trace_id FROM t_kds_replication_dead_letter_audit", String.class));
    }

    @Configuration
    @EnableTransactionManagement
    static class Config {
        @Bean DataSource dataSource() {
            return new EmbeddedDatabaseBuilder().setType(EmbeddedDatabaseType.H2)
                    .setName("kds-audit;MODE=MySQL;DB_CLOSE_DELAY=-1").build();
        }
        @Bean JdbcTemplate jdbcTemplate(DataSource dataSource) { return new JdbcTemplate(dataSource); }
        @Bean PlatformTransactionManager transactionManager(DataSource dataSource) {
            return new DataSourceTransactionManager(dataSource);
        }
        @Bean KdsReplicationAuditService auditService(JdbcTemplate jdbcTemplate) {
            return new KdsReplicationAuditService(jdbcTemplate);
        }
        @Bean KdsCashierAuthorityService authorityService(JdbcTemplate jdbcTemplate) {
            return new KdsCashierAuthorityService(jdbcTemplate);
        }
    }
}
