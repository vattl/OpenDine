package com.lanf.kds.service;

import com.lanf.database.KdsCloudAuthorityFailClosedSchemaMigration;
import com.lanf.database.KdsDevicePairingSchemaMigration;
import com.lanf.database.KdsV2RetentionArchiveSchemaMigration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Read-only startup guard: durable KDS V2 state must never fall back to process memory. */
@Component
public class KdsV2SchemaReadiness implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(KdsV2SchemaReadiness.class);
    private final JdbcTemplate jdbc;

    public KdsV2SchemaReadiness(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            jdbc.queryForList("SELECT shop_id,command_id,actor_id,actor_type,command_type,"
                    + "request_fingerprint,request_schema_version,status,result_json "
                    + "FROM t_kds_v2_command WHERE 1=0");
            jdbc.queryForList("SELECT shop_id,event_seq,updated_at FROM t_kds_v2_event_cursor WHERE 1=0");
            jdbc.queryForList("SELECT shop_id,event_seq,event_id,command_id,schema_version,"
                    + "entity_id,business_revision,event_json,created_at "
                    + "FROM t_kds_v2_event WHERE 1=0");
            jdbc.queryForList("SELECT order_id,shop_id,revision FROM t_kds_order WHERE 1=0");
            jdbc.queryForList("SELECT id,shop_id,client_order_id,revision FROM t_order WHERE 1=0");
            jdbc.queryForList("SELECT shop_id,authority_mode,protocol_version,updated_at "
                    + "FROM t_kds_shop_authority WHERE 1=0");
            jdbc.queryForList("SELECT id,device_code,token_hash,token_expires_at,token_revoked_at,enabled "
                    + "FROM t_kds_device WHERE 1=0");
            jdbc.queryForList("SELECT id,shop_id,device_code,code_hash,expires_at,consumed_at,created_by "
                    + "FROM t_kds_device_pairing_ticket WHERE 1=0");

            requireIndex("t_kds_v2_command", "PRIMARY");
            requireIndex("t_kds_v2_event_cursor", "PRIMARY");
            requireIndex("t_kds_v2_event", "PRIMARY");
            requireIndex("t_kds_v2_event", "uk_kds_v2_event_id");
            requireIndex("t_kds_shop_authority", "PRIMARY");
            requireIndex("t_kds_device", "uk_kds_device_token_hash");
            requireIndex("t_kds_device_pairing_ticket", "uk_kds_pairing_code_hash");
            requireIndex("t_kds_device_pairing_ticket", "idx_kds_pairing_device_status");
            requireInnoDb("t_kds_v2_command");
            requireInnoDb("t_kds_v2_event_cursor");
            requireInnoDb("t_kds_v2_event");
            requireInnoDb("t_kds_shop_authority");
            requireInnoDb("t_kds_device_pairing_ticket");
            requireInnoDb("t_kds_v2_command_archive");
            requireInnoDb("t_kds_v2_event_archive");
            requireV010Migration();
            requireV011Migration();
            requireV012Migration();
        } catch (Exception ex) {
            throw new IllegalStateException("Apply db/migration/V008__kds_cloud_authority.sql and "
                    + "V009__kds_device_token_lifecycle.sql and "
                    + "V010__kds_cloud_authority_fail_closed.sql and "
                    + "V011__kds_device_pairing_ticket.sql and "
                    + "V012__kds_v2_retention_archive.sql with the explicit KDS migrations "
                    + "before starting this version", ex);
        }
        log.info("[kds-v2-schema-readiness] command ledger, event log, token lifecycle, "
                + "fail-closed authority, one-time pairing, and retention archive verified");
    }

    private void requireIndex(String table, String index) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.STATISTICS "
                        + "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND INDEX_NAME=?",
                Integer.class, table, index);
        if (count == null || count < 1) {
            throw new IllegalStateException("missing " + table + " index " + index);
        }
    }

    private void requireInnoDb(String table) {
        String engine = jdbc.queryForObject(
                "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?",
                String.class, table);
        if (!"InnoDB".equalsIgnoreCase(engine)) {
            throw new IllegalStateException(table + " must use InnoDB");
        }
    }

    private void requireV010Migration() throws Exception {
        java.util.List<String> checksums = jdbc.queryForList(
                "SELECT checksum FROM t_app_schema_version WHERE version='V010'",
                String.class);
        String expected = KdsCloudAuthorityFailClosedSchemaMigration.checksum();
        if (checksums.size() != 1 || !expected.equals(checksums.get(0))) {
            throw new IllegalStateException("missing or mismatched V010 migration marker");
        }
    }

    private void requireV011Migration() throws Exception {
        java.util.List<String> checksums = jdbc.queryForList(
                "SELECT checksum FROM t_app_schema_version WHERE version='V011'",
                String.class);
        String expected = KdsDevicePairingSchemaMigration.checksum();
        if (checksums.size() != 1 || !expected.equals(checksums.get(0))) {
            throw new IllegalStateException("missing or mismatched V011 migration marker");
        }
    }

    private void requireV012Migration() throws Exception {
        java.util.List<String> checksums = jdbc.queryForList(
                "SELECT checksum FROM t_app_schema_version WHERE version='V012'",
                String.class);
        String expected = KdsV2RetentionArchiveSchemaMigration.checksum();
        if (checksums.size() != 1 || !expected.equals(checksums.get(0))) {
            throw new IllegalStateException("missing or mismatched V012 migration marker");
        }
    }
}
