package com.lanf.database;

import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import java.sql.*;
import java.security.MessageDigest;
import java.util.List;

/** Explicit CLI, not a Spring bean. DDL is never run by the business application. */
public final class AuditSchemaMigration {
    public static final String RESOURCE = "db/migration/V007__audit.sql";
    private AuditSchemaMigration() {}
    public static void main(String[] args) throws Exception {
        String url = required("MIGRATION_JDBC_URL");
        if (!url.startsWith("jdbc:mysql:")) throw new IllegalArgumentException("Explicit MySQL JDBC URL required");
        try (Connection connection = DriverManager.getConnection(url, required("MIGRATION_DB_USER"), required("MIGRATION_DB_PASSWORD"))) {
            apply(connection);
        }
        System.out.println("V007 migration verified and recorded");
    }
    public static void apply(Connection connection) throws Exception {
        JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        Integer acquired = jdbc.queryForObject("SELECT GET_LOCK('lanf_audit_schema',30)", Integer.class);
        if (!Integer.valueOf(1).equals(acquired)) throw new IllegalStateException("Migration lock unavailable");
        try {
            jdbc.execute("CREATE TABLE IF NOT EXISTS t_app_schema_version (version VARCHAR(32) PRIMARY KEY, checksum VARCHAR(64) NOT NULL, applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)");
            List<String> checksums = jdbc.queryForList("SELECT checksum FROM t_app_schema_version WHERE version='V007'",String.class);
            String checksum = checksum();
            if (!checksums.isEmpty()) {
                if (!checksum.equals(checksums.get(0))) throw new IllegalStateException("Applied migration checksum mismatch");
                return;
            }
            // Each statement is restartable: MySQL DDL is not transactionally rolled back.
            ScriptUtils.executeSqlScript(connection,new ClassPathResource(RESOURCE));
            jdbc.update("INSERT INTO t_app_schema_version(version,checksum) VALUES ('V007',?)",checksum);
        } finally { jdbc.queryForObject("SELECT RELEASE_LOCK('lanf_audit_schema')",Integer.class); }
    }
    public static String checksum() throws Exception {
        byte[] bytes;
        try (java.io.InputStream input = new ClassPathResource(RESOURCE).getInputStream()) {
            bytes = org.springframework.util.StreamUtils.copyToByteArray(input);
        }
        StringBuilder result = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(new String(bytes, java.nio.charset.StandardCharsets.UTF_8).replace("\r\n", "\n").getBytes(java.nio.charset.StandardCharsets.UTF_8))) result.append(String.format("%02x",value & 255));
        return result.toString();
    }
    private static String required(String key) {
        String value = System.getenv(key);
        if (value == null || value.trim().isEmpty()) throw new IllegalStateException("Missing " + key);
        return value;
    }
}
