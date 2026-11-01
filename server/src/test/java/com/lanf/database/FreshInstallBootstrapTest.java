package com.lanf.database;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class FreshInstallBootstrapTest {
    @Test
    void refusesWeakOrUnusableInitialCredentialsBeforeDatabaseAccess() {
        assertDoesNotThrow(() -> FreshInstallBootstrap.validateIdentity("owner", "a-random-password-123", "First Shop"));
        assertThrows(IllegalArgumentException.class, () -> FreshInstallBootstrap.validateIdentity("owner", "short", "Shop"));
        assertThrows(IllegalArgumentException.class, () -> FreshInstallBootstrap.validateIdentity("owner", " a-random-password-123", "Shop"));
        assertThrows(IllegalArgumentException.class, () -> FreshInstallBootstrap.validateIdentity("owner", String.join("", Collections.nCopies(25, "密")), "Shop"));
        assertThrows(IllegalArgumentException.class, () -> FreshInstallBootstrap.validateIdentity("owner'", "a-random-password-123", "Shop"));
        assertThrows(IllegalArgumentException.class, () -> FreshInstallBootstrap.validateIdentity("owner", "a-random-password-123", " "));
        assertThrows(IllegalArgumentException.class, () -> FreshInstallBootstrap.required(Collections.emptyMap(), "BOOTSTRAP_ADMIN_PASSWORD"));
    }

    @Test
    void nonemptyOrUnknownDatabaseFailsClosed() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), eq(Integer.class))).thenReturn(1);
        assertThrows(IllegalStateException.class, () -> FreshInstallBootstrap.requireEmptyDatabase(jdbc));
        when(jdbc.queryForObject(anyString(), eq(Integer.class))).thenReturn(null);
        assertThrows(IllegalStateException.class, () -> FreshInstallBootstrap.requireEmptyDatabase(jdbc));
        when(jdbc.queryForObject(anyString(), eq(Integer.class))).thenReturn(0);
        assertDoesNotThrow(() -> FreshInstallBootstrap.requireEmptyDatabase(jdbc));
    }

    @Test
    void seedFailureRollsBackEarlierPermissionWritesAndRestoresAutoCommit() throws Exception {
        try (Connection connection = DriverManager.getConnection("jdbc:h2:mem:bootstrap_rollback;MODE=MySQL", "sa", "")) {
            JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
            jdbc.execute("CREATE TABLE t_api_permission(permission_code VARCHAR(100))");
            jdbc.execute("CREATE TABLE t_permission(permission_code VARCHAR(100) PRIMARY KEY,permission_name VARCHAR(100),module VARCHAR(100))");
            jdbc.update("INSERT INTO t_api_permission VALUES ('order:view')");
            // The following identity write must fail: t_admin intentionally does not exist.
            assertThrows(Exception.class, () -> FreshInstallBootstrap.seedIdentity(connection, "owner", "a-random-password-123", "Shop"));
            assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM t_permission", Integer.class));
            assertTrue(connection.getAutoCommit());
        }
    }

    @Test
    void missingApiRoutesAreSeededWithoutReplacingStrictMappings() throws Exception {
        try (Connection connection = DriverManager.getConnection("jdbc:h2:mem:bootstrap_mappings;MODE=MySQL", "sa", "")) {
            JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
            jdbc.execute("CREATE TABLE t_api_permission(method VARCHAR(10),path_pattern VARCHAR(255) PRIMARY KEY,permission_code VARCHAR(255))");
            jdbc.update("INSERT INTO t_api_permission VALUES ('PUT','/admin/subscribe/scenes/','admin:super')");
            FreshInstallBootstrap.seedMissingApiMappings(jdbc);
            assertEquals("admin:super", jdbc.queryForObject("SELECT permission_code FROM t_api_permission WHERE path_pattern='/admin/subscribe/scenes/'", String.class));
            assertEquals("GET", jdbc.queryForObject("SELECT method FROM t_api_permission WHERE path_pattern='/user/notifications/sync'", String.class));
            assertEquals("POST", jdbc.queryForObject("SELECT method FROM t_api_permission WHERE path_pattern='/user/notifications/ack'", String.class));
            assertEquals(4, jdbc.queryForObject("SELECT COUNT(*) FROM t_api_permission", Integer.class));
        }
    }

    @Test
    void acceptsUtf8BomWithoutChangingMigrationFiles() throws Exception {
        try (Connection connection = DriverManager.getConnection("jdbc:h2:mem:bootstrap_bom;MODE=MySQL", "sa", "")) {
            FreshInstallBootstrap.executeSql(connection, "\uFEFF-- Existing UTF-8 migration\nCREATE TABLE bom_example(id INT);".getBytes(StandardCharsets.UTF_8));
            JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
            assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM bom_example", Integer.class));
        }
    }

    @Test
    void honorsMysqlDelimiterSectionsWithoutIgnoringErrors() throws Exception {
        try (Connection connection = DriverManager.getConnection("jdbc:h2:mem:bootstrap_delimiter;MODE=MySQL", "sa", "")) {
            FreshInstallBootstrap.executeSql(connection, ("CREATE TABLE sample(id INT PRIMARY KEY);\n"
                    + "DELIMITER $\n$\nINSERT INTO sample VALUES(1)$\n$\nDELIMITER ;\nINSERT INTO sample VALUES(2);").getBytes(StandardCharsets.UTF_8));
            JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
            assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM sample", Integer.class));
            assertThrows(Exception.class, () -> FreshInstallBootstrap.executeSql(connection,
                    "INSERT INTO nonexistent VALUES(1);".getBytes(StandardCharsets.UTF_8)));
        }
    }
}
