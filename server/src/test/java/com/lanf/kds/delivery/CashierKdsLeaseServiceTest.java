package com.lanf.kds.delivery;

import com.lanf.kds.service.KdsCashierAuthorityService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabase;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class CashierKdsLeaseServiceTest {
    private EmbeddedDatabase database;
    private JdbcTemplate jdbc;
    private CashierKdsLeaseService service;

    @BeforeEach
    void setUp() {
        database = new EmbeddedDatabaseBuilder().setType(EmbeddedDatabaseType.H2)
                .setName("cashier-kds-lease-" + System.nanoTime() + ";MODE=MySQL").build();
        jdbc = new JdbcTemplate(database);
        jdbc.execute("CREATE TABLE t_kds_authority_config_version (shop_id INT PRIMARY KEY, cashier_device_code VARCHAR(64), version BIGINT, snapshot_hash VARCHAR(64))");
        jdbc.execute("CREATE TABLE t_kds_delivery_consumer (shop_id INT PRIMARY KEY, device_code VARCHAR(64), authority_epoch BIGINT DEFAULT 0, lease_token_hash VARCHAR(64), lease_until TIMESTAMP, ack_cursor BIGINT DEFAULT 0, last_delivered_cursor BIGINT DEFAULT 0, bootstrap_base_cursor BIGINT DEFAULT 0, bootstrap_required TINYINT DEFAULT 1, client_version VARCHAR(64), last_seen_at TIMESTAMP, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE t_kds_delivery_event (id BIGINT AUTO_INCREMENT PRIMARY KEY, shop_id INT)");
        jdbc.update("INSERT INTO t_kds_authority_config_version(shop_id,cashier_device_code,version) VALUES (1,'POS-A',1)");
        service = new CashierKdsLeaseService(jdbc, new KdsCashierAuthorityService(jdbc));
    }

    @AfterEach void tearDown() { database.shutdown(); }

    @Test
    void acquireRenewAndFenceWrongEpochWithoutPersistingPlainToken() {
        Map<String, Object> acquire = new LinkedHashMap<>();
        acquire.put("action", "ACQUIRE");
        Map<String, Object> leased = service.lease(1, "POS-A", acquire);
        long epoch = ((Number) leased.get("authorityEpoch")).longValue();
        String token = String.valueOf(leased.get("leaseToken"));
        assertEquals(1L, epoch);
        assertTrue(token.length() >= 32);
        assertNotEquals(token, jdbc.queryForObject("SELECT lease_token_hash FROM t_kds_delivery_consumer WHERE shop_id=1", String.class));

        Map<String, Object> renew = new LinkedHashMap<>();
        renew.put("action", "RENEW"); renew.put("authorityEpoch", epoch); renew.put("leaseToken", token);
        assertEquals(epoch, ((Number) service.lease(1, "POS-A", renew).get("authorityEpoch")).longValue());

        renew.put("authorityEpoch", epoch + 1);
        CashierKdsDeliveryException fenced = assertThrows(CashierKdsDeliveryException.class,
                () -> service.lease(1, "POS-A", renew));
        assertEquals(409, fenced.getHttpStatus());
    }
}
