package com.lanf.database;

import com.lanf.util.AdminPasswordUtil;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.EncodedResource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.jdbc.datasource.init.ScriptUtils;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Map;

/** Operator-run, empty-database-only installer. Never invoked by application startup. */
public final class FreshInstallBootstrap {
    private FreshInstallBootstrap() { }

    public static void main(String[] args) {
        org.slf4j.Logger rootLogger = org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME);
        if (rootLogger instanceof ch.qos.logback.classic.Logger) {
            ((ch.qos.logback.classic.Logger) rootLogger).setLevel(ch.qos.logback.classic.Level.INFO);
        }
        try {
            Map<String, String> env = System.getenv();
            String username = required(env, "BOOTSTRAP_ADMIN_USERNAME");
            String password = required(env, "BOOTSTRAP_ADMIN_PASSWORD");
            String shop = required(env, "BOOTSTRAP_SHOP_NAME");
            validateIdentity(username, password, shop);
            String url = required(env, "MIGRATION_JDBC_URL");
            if (!url.startsWith("jdbc:mysql:")) {
                throw new BootstrapInputException("MIGRATION_JDBC_URL must select a MySQL database");
            }
            if (!"YES".equals(required(env, "BOOTSTRAP_CONFIRM_EMPTY_DATABASE"))) {
                throw new BootstrapInputException("Set BOOTSTRAP_CONFIRM_EMPTY_DATABASE=YES only for a new empty database");
            }
            Path repository = Paths.get(required(env, "BOOTSTRAP_REPOSITORY_ROOT"));
            try (Connection connection = DriverManager.getConnection(url,
                    required(env, "MIGRATION_DB_USER"), required(env, "MIGRATION_DB_PASSWORD"))) {
                initialize(connection, repository, username, password, shop);
            }
            System.out.println("Fresh installation complete. Administrator created; first shop is closed for ordering.");
        } catch (Exception failure) {
            // JDBC exceptions can contain SQL and connection details. Do not print secrets or a raw stack trace.
            System.err.println("Bootstrap FAILED (" + failure.getClass().getSimpleName()
                    + "). Check the last stage above. Existing/partially initialized databases are never overwritten.");
            if (failure instanceof BootstrapInputException) System.err.println(failure.getMessage());
            for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
                if (cause instanceof java.sql.SQLException) {
                    java.sql.SQLException sql = (java.sql.SQLException) cause;
                    String state = sql.getSQLState();
                    System.err.println("MySQL diagnostic: SQLState="
                            + (state != null && state.matches("[A-Za-z0-9]+") ? state : "unknown")
                            + ", vendorCode=" + sql.getErrorCode());
                    break;
                }
            }
            System.exit(1);
        }
    }

    static String required(Map<String, String> env, String key) {
        String value = env.get(key);
        if (value == null || value.trim().isEmpty()) {
            throw new BootstrapInputException("Missing " + key);
        }
        return value;
    }

    static void validateIdentity(String username, String password, String shop) {
        if (!username.matches("[A-Za-z0-9_.-]{3,22}")) {
            throw new BootstrapInputException("Administrator username must be 3-22 ASCII letters/digits/._-");
        }
        int passwordBytes = password.getBytes(StandardCharsets.UTF_8).length;
        if (passwordBytes < 16 || passwordBytes > 72 || !password.equals(password.trim())) {
            throw new BootstrapInputException("Administrator password must be 16-72 UTF-8 bytes without surrounding whitespace");
        }
        if (shop.trim().isEmpty() || shop.length() > 64) {
            throw new BootstrapInputException("Shop name must contain 1-64 characters");
        }
    }

    static void requireEmptyDatabase(JdbcTemplate jdbc) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()", Integer.class);
        if (count == null || count != 0) {
            System.err.println("Target database is not empty; initialization refused before writing anything.");
            throw new IllegalStateException("Target database is not empty; refusing initialization");
        }
    }

    public static void initialize(Connection connection, Path repository, String username,
                                  String password, String shop) throws Exception {
        validateIdentity(username, password, shop);
        JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        System.out.println("Stage: verify empty MySQL 8 database and acquire bootstrap lock");
        if (!connection.getMetaData().getDatabaseProductName().equals("MySQL")
                || connection.getMetaData().getDatabaseMajorVersion() < 8 || connection.getCatalog() == null) {
            throw new BootstrapInputException("Select an empty MySQL 8 database");
        }
        Integer locked = jdbc.queryForObject("SELECT GET_LOCK('opendine_fresh_install',0)", Integer.class);
        if (!Integer.valueOf(1).equals(locked)) {
            throw new IllegalStateException("Another bootstrap holds the lock");
        }
        try {
            requireEmptyDatabase(jdbc);
            Path schema = repository.resolve("deploy/sql/init.sql");
            Path rbac = repository.resolve("server/docs/db_migration_rbac_v2.sql");
            Path api = repository.resolve("server/docs/db_migration_api_permission_full.sql");
            Path projection = repository.resolve("server/docs/db_migration_kds_projection_intent.sql");
            Path revision = repository.resolve("server/docs/db_migration_kds_shared_revision.sql");
            Path reportRecovery = repository.resolve("server/docs/db_migration_report_job_recovery.sql");
            Path shopFlow = repository.resolve("server/docs/db_migration_shop_settle_flow.sql");
            for (Path input : Arrays.asList(schema, rbac, api, projection, revision, reportRecovery, shopFlow)) {
                if (!Files.isRegularFile(input)) throw new BootstrapInputException("Missing bootstrap SQL input");
            }
            Resource[] migrations = new PathMatchingResourcePatternResolver()
                    .getResources("classpath*:db/migration/V*.sql");
            Arrays.sort(migrations, Comparator.comparing(Resource::getFilename));
            if (migrations.length == 0) throw new IllegalStateException("No versioned migrations in JAR");
            System.out.println("Stage: import fresh-install baseline");
            executeSql(connection, Files.readAllBytes(schema));
            System.out.println("Stage: seed role catalog");
            executeSql(connection, Files.readAllBytes(rbac));
            System.out.println("Stage: seed API permission catalog");
            executeSql(connection, Files.readAllBytes(api));
            jdbc.update("INSERT INTO t_role(role_code,role_name,remark,sort_order,version) VALUES ('super_admin','System administrator','Fresh installation owner',0,1)");
            for (Resource resource : migrations) {
                String name = resource.getFilename();
                String version = name.substring(0, name.indexOf("__"));
                System.out.println("Stage: apply " + name);
                switch (version) {
                    case "V007": AuditSchemaMigration.apply(connection); break;
                    case "V008": KdsCloudAuthoritySchemaMigration.apply(connection); break;
                    case "V009": KdsDeviceTokenSchemaMigration.apply(connection); break;
                    case "V010": KdsCloudAuthorityFailClosedSchemaMigration.apply(connection); break;
                    case "V011": KdsDevicePairingSchemaMigration.apply(connection); break;
                    case "V012": KdsV2RetentionArchiveSchemaMigration.apply(connection); break;
                    default:
                        byte[] sql;
                        try (java.io.InputStream stream = resource.getInputStream()) {
                            sql = org.springframework.util.StreamUtils.copyToByteArray(stream);
                        }
                        executeSql(connection, sql);
                        jdbc.update("INSERT INTO t_app_schema_version(version,checksum) VALUES (?,?)", version, checksum(sql));
                }
            }
            // These explicit historical prerequisites have no V-number. Do not invent version markers.
            for (Path input : Arrays.asList(projection, revision, reportRecovery, shopFlow)) {
                System.out.println("Stage: apply explicit prerequisite " + input.getFileName());
                executeSql(connection, Files.readAllBytes(input));
            }
            seedMissingApiMappings(jdbc);
            System.out.println("Stage: create administrator and first shop transactionally");
            seedIdentity(connection, username, password, shop);
            System.out.println("Stage: verify payment and KDS readiness");
            new PaymentSchemaReadiness(jdbc).verify();
            new com.lanf.kds.service.KdsV2SchemaReadiness(jdbc).run(null);
            new com.lanf.kds.delivery.CashierKdsProjectionIntentReadiness(jdbc).run(null);
            new com.lanf.kds.replication.KdsReplicationSchemaReadinessValidator(jdbc).run(null);
            jdbc.queryForList("SELECT run_token,lease_until FROM t_report_export_job WHERE 1=0");
            jdbc.queryForList("SELECT shift_required,settle_required FROM t_shop WHERE 1=0");
            if (!Integer.valueOf(1).equals(jdbc.queryForObject("SELECT COUNT(*) FROM t_report_job_admission WHERE id=1", Integer.class))) {
                throw new IllegalStateException("Report recovery admission row is missing");
            }
        } finally {
            jdbc.queryForObject("SELECT RELEASE_LOCK('opendine_fresh_install')", Integer.class);
        }
    }

    static void seedMissingApiMappings(JdbcTemplate jdbc) {
        // Current controller/inventory routes absent from historical SQL. INSERT IGNORE never
        // replaces a stricter existing mapping, and this runs only after the empty-database guard.
        for (String[] mapping : new String[][] {
                {"PUT", "/admin/subscribe/scenes/", "settings:manage|order:operate"},
                {"*", "/admin/subscribe/", "settings:manage|order:operate"},
                {"GET", "/user/notifications/sync", "user:notification|cashier:operate"},
                {"POST", "/user/notifications/ack", "user:notification|cashier:operate"}}) {
            jdbc.update("INSERT IGNORE INTO t_api_permission(method,path_pattern,permission_code) VALUES (?,?,?)",
                    mapping[0], mapping[1], mapping[2]);
        }
    }

    static void seedIdentity(Connection connection, String username, String password, String shop) throws Exception {
        boolean previousAutoCommit = connection.getAutoCommit();
        connection.setAutoCommit(false);
        JdbcTemplate jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        try {
            // Mappings can refer to permission atoms absent from the legacy catalog. Materialize them
            // only for this new installation, without rewriting the database-authoritative mappings.
            for (String expression : jdbc.queryForList("SELECT DISTINCT permission_code FROM t_api_permission", String.class)) {
                for (String code : expression.split("\\|")) {
                    code = code.trim();
                    if (!code.isEmpty()) jdbc.update("INSERT IGNORE INTO t_permission(permission_code,permission_name,module) VALUES (?,?,'System')", code, code);
                }
            }
            jdbc.update("INSERT INTO t_admin(userName,password,real_name,account_status) VALUES (?,?,?,'ACTIVE')",
                    username, AdminPasswordUtil.encode(password), username);
            Integer adminId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Integer.class);
            jdbc.update("INSERT INTO t_admin_role(admin_id,role_id) SELECT ?,id FROM t_role WHERE role_code='super_admin'", adminId);
            jdbc.update("INSERT IGNORE INTO t_role_permission(role_id,permission_id) SELECT r.id,p.id FROM t_role r CROSS JOIN t_permission p WHERE r.role_code='super_admin'");
            jdbc.update("INSERT INTO t_shop(name,code,status,ordering_open) VALUES (?,'FIRST',1,0)", shop);
            Integer shopId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Integer.class);
            jdbc.update("INSERT INTO t_admin_shop(admin_id,shop_id) VALUES (?,?)", adminId, shopId);
            jdbc.update("INSERT INTO t_kds_shop_authority(shop_id,authority_mode,protocol_version) VALUES (?,'cloud',2)", shopId);
            // Historical migrations include demonstration update policies and template identifiers.
            jdbc.update("UPDATE t_admin_app_version SET enabled=0 WHERE download_url IS NULL OR download_url=''");
            jdbc.update("UPDATE t_subscribe_scene_template SET is_active=0");
            connection.commit();
        } catch (Exception failure) {
            connection.rollback();
            throw failure;
        } finally {
            connection.setAutoCommit(previousAutoCommit);
        }
    }

    /** Honor mysql-client DELIMITER directives in immutable migration V026. */
    static void executeSql(Connection connection, byte[] bytes) {
        String delimiter = ";";
        StringBuilder section = new StringBuilder();
        String script = new String(bytes, StandardCharsets.UTF_8).replace("\r\n", "\n");
        // UTF-8 BOM is an encoding marker, not a MySQL token. Keep original bytes for checksums.
        if (script.startsWith("\uFEFF")) script = script.substring(1);
        for (String line : script.split("\n", -1)) {
            if (line.trim().toUpperCase(java.util.Locale.ROOT).startsWith("DELIMITER ")) {
                executeSection(connection, section.toString(), delimiter);
                section.setLength(0);
                delimiter = line.trim().substring("DELIMITER ".length()).trim();
            } else {
                section.append(line).append('\n');
            }
        }
        executeSection(connection, section.toString(), delimiter);
    }

    private static void executeSection(Connection connection, String sql, String delimiter) {
        if (!sql.trim().isEmpty()) {
            ScriptUtils.executeSqlScript(connection,
                    new EncodedResource(new ByteArrayResource(sql.getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8),
                    false, false, "--", delimiter, "/*", "*/");
        }
    }

    private static String checksum(byte[] bytes) throws Exception {
        byte[] normalized = new String(bytes, StandardCharsets.UTF_8).replace("\r\n", "\n").getBytes(StandardCharsets.UTF_8);
        StringBuilder result = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(normalized)) result.append(String.format("%02x", value & 255));
        return result.toString();
    }

    private static final class BootstrapInputException extends IllegalArgumentException {
        private BootstrapInputException(String message) { super(message); }
    }
}
