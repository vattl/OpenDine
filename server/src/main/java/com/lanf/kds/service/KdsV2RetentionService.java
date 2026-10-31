package com.lanf.kds.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Service managing retention, cold archiving, and batch cleanups for KDS V2 commands and events.
 * Prevents unbounded hot table growth and supports historical troubleshooting.
 */
@Service
public class KdsV2RetentionService {

    private static final Logger log = LoggerFactory.getLogger(KdsV2RetentionService.class);

    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private ObjectMapper objectMapper;

    /**
     * Ensures archive tables exist before executing archiving logic.
     */
    public void ensureArchiveTablesExist() {
        try {
            jdbc.execute("CREATE TABLE IF NOT EXISTS t_kds_v2_command_archive ("
                    + "shop_id INT NOT NULL, command_id VARCHAR(128) NOT NULL, "
                    + "actor_id VARCHAR(64) NOT NULL, actor_type VARCHAR(32) NOT NULL, "
                    + "command_type VARCHAR(64) NOT NULL, request_fingerprint CHAR(64) NOT NULL, "
                    + "request_schema_version VARCHAR(32) NOT NULL, status VARCHAR(16) NOT NULL, "
                    + "result_json LONGTEXT NULL, created_at DATETIME NOT NULL, "
                    + "updated_at DATETIME NOT NULL, applied_at DATETIME NULL, "
                    + "archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, "
                    + "PRIMARY KEY (shop_id, command_id), "
                    + "KEY idx_kds_v2_cmd_arch_status_time (status, updated_at), "
                    + "KEY idx_kds_v2_cmd_arch_archived_at (archived_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            jdbc.execute("CREATE TABLE IF NOT EXISTS t_kds_v2_event_archive ("
                    + "shop_id INT NOT NULL, event_seq BIGINT NOT NULL, "
                    + "event_id VARCHAR(128) NOT NULL, command_id VARCHAR(128) NOT NULL DEFAULT 'system', "
                    + "schema_version VARCHAR(32) NOT NULL DEFAULT '2.0', entity_id VARCHAR(64) NOT NULL DEFAULT '', "
                    + "business_revision BIGINT NOT NULL DEFAULT 0, event_json LONGTEXT NOT NULL, "
                    + "created_at DATETIME NOT NULL, archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, "
                    + "PRIMARY KEY (shop_id, event_seq), UNIQUE KEY uk_kds_v2_event_arch_id (shop_id, event_id), "
                    + "KEY idx_kds_v2_event_arch_created (created_at), "
                    + "KEY idx_kds_v2_event_arch_archived_at (archived_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        } catch (Exception ex) {
            log.warn("[kds-retention] failed to ensure archive tables exist: {}", ex.getMessage());
        }
    }

    /**
     * Archives terminal commands (APPLIED or REJECTED) older than retentionDays for a specific shop.
     * Copies records in batch into t_kds_v2_command_archive, then removes them from t_kds_v2_command.
     *
     * @param shopId shop identifier
     * @param retentionDays retention window in days (e.g. 7 or 30)
     * @param batchSize batch limit (e.g. 100 to 1000)
     * @return number of commands archived
     */
    @Transactional(rollbackFor = Exception.class)
    public int archiveTerminalCommands(int shopId, int retentionDays, int batchSize) {
        if (shopId <= 0 || retentionDays < 0) {
            throw new IllegalArgumentException("invalid shopId or retentionDays");
        }
        ensureArchiveTablesExist();
        int limit = Math.max(1, Math.min(batchSize, 2000));

        List<String> commandIds = jdbc.queryForList(
                "SELECT command_id FROM t_kds_v2_command "
                        + "WHERE shop_id=? AND status IN ('APPLIED', 'REJECTED') "
                        + "AND updated_at < DATE_SUB(NOW(), INTERVAL ? DAY) "
                        + "ORDER BY updated_at ASC LIMIT ?",
                String.class, shopId, retentionDays, limit);

        if (commandIds.isEmpty()) {
            return 0;
        }

        String inSql = String.join(",", Collections.nCopies(commandIds.size(), "?"));
        List<Object> params = new ArrayList<>();
        params.add(shopId);
        params.addAll(commandIds);

        // 1. Copy into archive
        jdbc.update(
                "INSERT IGNORE INTO t_kds_v2_command_archive "
                        + "(shop_id, command_id, actor_id, actor_type, command_type, "
                        + "request_fingerprint, request_schema_version, status, result_json, "
                        + "created_at, updated_at, applied_at, archived_at) "
                        + "SELECT shop_id, command_id, actor_id, actor_type, command_type, "
                        + "request_fingerprint, request_schema_version, status, result_json, "
                        + "created_at, updated_at, applied_at, NOW() "
                        + "FROM t_kds_v2_command WHERE shop_id=? AND command_id IN (" + inSql + ")",
                params.toArray());

        // 2. Remove from hot table
        int deleted = jdbc.update(
                "DELETE FROM t_kds_v2_command WHERE shop_id=? AND command_id IN (" + inSql + ")",
                params.toArray());

        log.info("[kds-retention] shop {} archived {} terminal commands (batch limit {})",
                shopId, deleted, limit);
        return deleted;
    }

    /**
     * Archives terminal commands across all shops.
     */
    public int archiveTerminalCommandsAllShops(int retentionDays, int batchSize) {
        ensureArchiveTablesExist();
        List<Integer> shopIds = jdbc.queryForList(
                "SELECT DISTINCT shop_id FROM t_kds_v2_command WHERE status IN ('APPLIED', 'REJECTED')",
                Integer.class);
        int total = 0;
        for (Integer shopId : shopIds) {
            if (shopId != null && shopId > 0) {
                total += archiveTerminalCommands(shopId, retentionDays, batchSize);
            }
        }
        return total;
    }

    /**
     * Archives events older than beforeEventSeq into t_kds_v2_event_archive, then removes them from t_kds_v2_event.
     *
     * @param shopId shop identifier
     * @param beforeEventSeq sequence cutoff
     * @param batchSize batch limit
     * @return number of events archived
     */
    @Transactional(rollbackFor = Exception.class)
    public int archivePrunedEvents(int shopId, long beforeEventSeq, int batchSize) {
        if (shopId <= 0 || beforeEventSeq <= 0) {
            return 0;
        }
        ensureArchiveTablesExist();
        int limit = Math.max(1, Math.min(batchSize, 2000));

        List<Long> seqs = jdbc.queryForList(
                "SELECT event_seq FROM t_kds_v2_event "
                        + "WHERE shop_id=? AND event_seq <= ? "
                        + "ORDER BY event_seq ASC LIMIT ?",
                Long.class, shopId, beforeEventSeq, limit);

        if (seqs.isEmpty()) {
            return 0;
        }

        String inSql = String.join(",", Collections.nCopies(seqs.size(), "?"));
        List<Object> params = new ArrayList<>();
        params.add(shopId);
        params.addAll(seqs);

        // Copy into event archive
        jdbc.update(
                "INSERT IGNORE INTO t_kds_v2_event_archive "
                        + "(shop_id, event_seq, event_id, command_id, schema_version, "
                        + "entity_id, business_revision, event_json, created_at, archived_at) "
                        + "SELECT shop_id, event_seq, event_id, command_id, schema_version, "
                        + "entity_id, business_revision, event_json, created_at, NOW() "
                        + "FROM t_kds_v2_event WHERE shop_id=? AND event_seq IN (" + inSql + ")",
                params.toArray());

        int deleted = jdbc.update(
                "DELETE FROM t_kds_v2_event WHERE shop_id=? AND event_seq IN (" + inSql + ")",
                params.toArray());

        log.info("[kds-retention] shop {} archived {} pruned events (cutoff seq {})",
                shopId, deleted, beforeEventSeq);
        return deleted;
    }
}
