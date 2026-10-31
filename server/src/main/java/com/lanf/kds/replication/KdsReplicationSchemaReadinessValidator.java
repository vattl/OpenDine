package com.lanf.kds.replication;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Read-only startup guard. Schema DDL remains an explicit operator-controlled migration step. */
@Component
public class KdsReplicationSchemaReadinessValidator implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(KdsReplicationSchemaReadinessValidator.class);
    private final JdbcTemplate jdbc;

    public KdsReplicationSchemaReadinessValidator(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<String> missing = new ArrayList<>();
        for (ColumnRequirement requirement : Arrays.asList(
                column("t_kds_replication_event", "event_id"),
                column("t_kds_replication_event", "operation_id"),
                column("t_kds_replication_event", "request_fingerprint"),
                column("t_kds_replication_event", "publisher_device_code"),
                column("t_kds_replication_event", "payload_json"),
                column("t_kds_replication_aggregate", "last_order_revision"),
                column("t_kds_ticket", "row_version"),
                column("t_kds_ticket", "order_revision"),
                column("t_kds_replication_dead_letter_audit", "operator_admin_id"),
                column("t_kds_replication_dead_letter_audit", "operator_subject"),
                column("t_kds_replication_dead_letter_audit", "trace_id"),
                column("t_kds_authority_config_version", "cashier_device_code"),
                column("t_kds_authority_config_version", "version"),
                column("t_kds_authority_config_version", "snapshot_hash"))) {
            Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS "
                            + "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?",
                    Integer.class, requirement.table, requirement.column);
            if (count == null || count != 1) missing.add(requirement.table + "." + requirement.column);
        }
        for (IndexRequirement requirement : Arrays.asList(
                index("t_kds_replication_event", "uk_kds_replication_event_id", true),
                index("t_kds_replication_event", "uk_kds_replication_operation", true),
                index("t_kds_replication_aggregate", "PRIMARY", true),
                index("t_kds_replication_dead_letter_audit", "idx_kds_dead_letter_audit", false))) {
            Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.STATISTICS "
                            + "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND INDEX_NAME=? AND (?=0 OR NON_UNIQUE=0)",
                    Integer.class, requirement.table, requirement.index, requirement.unique ? 1 : 0);
            if (count == null || count < 1) missing.add(requirement.table + " index " + requirement.index);
        }
        if (!missing.isEmpty()) {
            throw new IllegalStateException("KDS authority/replication schema is not ready; apply "
                    + "docs/db_migration_kds_cashier_replication.sql and docs/db_migration_kds_authority_v2.sql. Missing: "
                    + String.join(", ", missing));
        }
        log.info("[kds-schema-readiness] authority/replication schema verified");
    }

    private static ColumnRequirement column(String table, String column) {
        return new ColumnRequirement(table, column);
    }

    private static IndexRequirement index(String table, String index, boolean unique) {
        return new IndexRequirement(table, index, unique);
    }

    private static final class ColumnRequirement {
        private final String table;
        private final String column;
        private ColumnRequirement(String table, String column) { this.table = table; this.column = column; }
    }

    private static final class IndexRequirement {
        private final String table;
        private final String index;
        private final boolean unique;
        private IndexRequirement(String table, String index, boolean unique) {
            this.table = table;
            this.index = index;
            this.unique = unique;
        }
    }
}
