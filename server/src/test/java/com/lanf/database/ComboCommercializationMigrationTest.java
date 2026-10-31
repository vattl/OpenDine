package com.lanf.database;

import org.junit.jupiter.api.Test;
import org.springframework.util.StreamUtils;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ComboCommercializationMigrationTest {

    private static final String RESOURCE =
            "db/migration/V034__combo_commercialization.sql";

    @Test
    void migrationAddsEveryCommercialColumnIdempotentlyWithoutExternalProcedure() throws Exception {
        try (InputStream input = Thread.currentThread().getContextClassLoader()
                .getResourceAsStream(RESOURCE)) {
            assertNotNull(input, RESOURCE);
            String sql = StreamUtils.copyToString(input, StandardCharsets.UTF_8);

            List<String> columns = Arrays.asList(
                    "limit_per_order",
                    "limit_per_user",
                    "limit_cycle",
                    "start_time",
                    "end_time",
                    "available_days",
                    "time_range_start",
                    "time_range_end",
                    "apply_dining_type",
                    "allow_coupon",
                    "daily_stock");

            for (String column : columns) {
                assertTrue(sql.contains("COLUMN_NAME='" + column + "'"),
                        "missing idempotent guard for " + column);
                assertTrue(sql.contains("ADD COLUMN " + column),
                        "missing DDL for " + column);
            }
            assertTrue(sql.contains("INFORMATION_SCHEMA.COLUMNS"));
            assertFalse(sql.contains("p_add_col_if_missing"));
        }
    }
}
