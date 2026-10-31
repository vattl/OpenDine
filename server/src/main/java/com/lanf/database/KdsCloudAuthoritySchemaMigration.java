package com.lanf.database;

import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.util.StreamUtils;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.List;

/** Explicit, operator-run migration for the KDS cloud-authority schema. */
public final class KdsCloudAuthoritySchemaMigration {
    public static final String RESOURCE = "db/migration/V008__kds_cloud_authority.sql";

    private KdsCloudAuthoritySchemaMigration() { }

    public static void main(String[] args) throws Exception {
        String url = required("MIGRATION_JDBC_URL");
        if (!url.startsWith("jdbc:mysql:")) {
            throw new IllegalArgumentException("Explicit MySQL JDBC URL required");
        }
        try (Connection connection = DriverManager.getConnection(
                url, required("MIGRATION_DB_USER"), required("MIGRATION_DB_PASSWORD"))) {
            apply(connection);
        }
        System.out.println("V008 KDS cloud-authority migration verified and recorded");
    }

    public static void apply(Connection connection) throws Exception {
        JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        Integer acquired = jdbc.queryForObject(
                "SELECT GET_LOCK('lanf_kds_cloud_authority_schema',30)", Integer.class);
        if (!Integer.valueOf(1).equals(acquired)) {
            throw new IllegalStateException("KDS migration lock unavailable");
        }
        try {
            jdbc.execute("CREATE TABLE IF NOT EXISTS t_app_schema_version ("
                    + "version VARCHAR(32) PRIMARY KEY,checksum VARCHAR(64) NOT NULL,"
                    + "applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)");
            List<String> checksums = jdbc.queryForList(
                    "SELECT checksum FROM t_app_schema_version WHERE version='V008'",
                    String.class);
            String expected = checksum();
            if (!checksums.isEmpty()) {
                if (!expected.equals(checksums.get(0))) {
                    throw new IllegalStateException("Applied V008 migration checksum mismatch");
                }
                return;
            }
            ScriptUtils.executeSqlScript(connection, new ClassPathResource(RESOURCE));
            jdbc.update(
                    "INSERT INTO t_app_schema_version(version,checksum) VALUES ('V008',?)",
                    expected);
        } finally {
            jdbc.queryForObject(
                    "SELECT RELEASE_LOCK('lanf_kds_cloud_authority_schema')", Integer.class);
        }
    }

    public static String checksum() throws Exception {
        byte[] bytes;
        try (java.io.InputStream input = new ClassPathResource(RESOURCE).getInputStream()) {
            bytes = StreamUtils.copyToByteArray(input);
        }
        byte[] normalized = new String(bytes, StandardCharsets.UTF_8)
                .replace("\r\n", "\n")
                .getBytes(StandardCharsets.UTF_8);
        StringBuilder result = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(normalized)) {
            result.append(String.format("%02x", value & 255));
        }
        return result.toString();
    }

    private static String required(String key) {
        String value = System.getenv(key);
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalStateException("Missing " + key);
        }
        return value;
    }
}
