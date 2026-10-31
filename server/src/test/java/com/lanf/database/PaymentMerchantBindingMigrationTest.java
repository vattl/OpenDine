package com.lanf.database;

import org.junit.jupiter.api.Test;
import org.springframework.util.StreamUtils;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PaymentMerchantBindingMigrationTest {

    @Test
    void migrationAddsRefundBindingCallbackIndexesAndUniqueOrderNumber() throws Exception {
        String resource = "db/migration/V033__payment_merchant_binding_hardening.sql";
        try (InputStream input = Thread.currentThread().getContextClassLoader().getResourceAsStream(resource)) {
            assertNotNull(input, resource);
            String sql = StreamUtils.copyToString(input, StandardCharsets.UTF_8);
            assertTrue(sql.contains("merchant_config_id"));
            assertTrue(sql.contains("expected_transaction_id"));
            assertTrue(sql.contains("expected_mch_id"));
            assertTrue(sql.contains("idx_payment_merchant_notify_serial"));
            assertTrue(sql.contains("idx_payment_merchant_history_notify_serial"));
            assertTrue(sql.contains("UNIQUE KEY uk_order_order_no"));
        }
    }
}
