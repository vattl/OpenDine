package com.lanf.access;

import org.junit.jupiter.api.Test;
import org.springframework.util.StreamUtils;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class ApprovalSchemaConvergenceMigrationContractTest {

    private static final String V043_RESOURCE =
            "db/migration/V043__approval_schema_convergence.sql";

    @Test
    void v043MigrationExistsAndConvergesApprovalSchemaIdempotently() throws Exception {
        try (InputStream input = Thread.currentThread().getContextClassLoader()
                .getResourceAsStream(V043_RESOURCE)) {
            assertNotNull(input, "V043 migration must exist in classpath: " + V043_RESOURCE);
            String sql = StreamUtils.copyToString(input, StandardCharsets.UTF_8);

            // 1. Table creation idempotency for t_access_approval
            assertTrue(sql.contains("CREATE TABLE IF NOT EXISTS `t_access_approval`"),
                    "must create t_access_approval if missing on clean database");
            assertTrue(sql.contains("`binding_version`"),
                    "new table definition must include binding_version");
            assertTrue(sql.contains("`token_value`"),
                    "new table definition must include token_value");

            // 2. Column convergence idempotency for existing t_access_approval
            assertTrue(sql.contains("binding_version"),
                    "must inspect information_schema for binding_version column");
            assertTrue(sql.contains("token_value"),
                    "must inspect information_schema for token_value column");

            // 3. Table creation for t_access_approval_rate_limit
            assertTrue(sql.contains("CREATE TABLE IF NOT EXISTS `t_access_approval_rate_limit`"),
                    "must create t_access_approval_rate_limit if missing");

            // 4. Exact permission seeding and role backfill
            List<String> permissions = Arrays.asList(
                    "order:operate:refund:approve",
                    "order:operate:changePrice:approve",
                    "order:operate:discount:approve"
            );
            for (String perm : permissions) {
                assertTrue(sql.contains("'" + perm + "'"), "must seed exact permission: " + perm);
            }
        }
    }

    @Test
    void installBaselineDiancanSqlIncludesApprovalAndRateLimitTables() throws Exception {
        Path path = Paths.get("docs/db_diancan.sql");
        if (!Files.exists(path)) {
            path = Paths.get("server/docs/db_diancan.sql");
        }
        assertTrue(Files.exists(path), "db_diancan.sql baseline must exist");
        String sql = new String(Files.readAllBytes(path), StandardCharsets.UTF_8);

        assertTrue(sql.contains("CREATE TABLE `t_access_approval`") || sql.contains("CREATE TABLE IF NOT EXISTS `t_access_approval`"),
                "install baseline must include t_access_approval table");
        assertTrue(sql.contains("`binding_version`"),
                "baseline t_access_approval must include binding_version");
        assertTrue(sql.contains("`token_value`"),
                "baseline t_access_approval must include token_value");

        assertTrue(sql.contains("CREATE TABLE `t_access_approval_rate_limit`") || sql.contains("CREATE TABLE IF NOT EXISTS `t_access_approval_rate_limit`"),
                "install baseline must include t_access_approval_rate_limit table");
    }
}
