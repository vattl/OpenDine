package com.lanf.kds.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Durable correctness boundary for KDS V2 commands.
 *
 * The caller owns the surrounding business transaction. A validated INSERT IGNORE plus
 * SELECT ... FOR UPDATE serializes concurrent uses of the same shop-scoped
 * command id. A rolled-back business mutation also rolls back its claim.
 */
@Service
public class KdsV2CommandLedger {

    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private ObjectMapper objectMapper;

    public Claim claim(int shopId, String commandId, String actorId, String actorType, String commandType, String schemaVersion, Map<String, Object> request) {
        if (commandId == null || commandId.isEmpty() || commandId.length() > 128) {
            throw new IllegalArgumentException("command_id must contain 1 to 128 characters");
        }
        String fingerprint = fingerprint(shopId, request);
        int inserted = jdbc.update(
                "INSERT IGNORE INTO t_kds_v2_command "
                        + "(shop_id,command_id,actor_id,actor_type,command_type,request_fingerprint,request_schema_version,status,created_at,updated_at) "
                        + "VALUES (?,?,?,?,?,?,?,'EXECUTING',NOW(),NOW())",
                shopId, commandId, actorId, actorType, commandType, fingerprint, schemaVersion);
        if (inserted == 1) {
            try {
                List<Map<String, Object>> archRows = jdbc.queryForList(
                        "SELECT request_fingerprint,status,result_json FROM t_kds_v2_command_archive "
                                + "WHERE shop_id=? AND command_id=?",
                        shopId, commandId);
                if (!archRows.isEmpty()) {
                    jdbc.update("DELETE FROM t_kds_v2_command WHERE shop_id=? AND command_id=? AND status='EXECUTING'",
                            shopId, commandId);
                    Map<String, Object> archRow = archRows.get(0);
                    if (!fingerprint.equals(String.valueOf(archRow.get("request_fingerprint")))) {
                        throw new KdsV2CommandConflictException(
                                "command_id was already used with different command data (archived)");
                    }
                    String archStatus = String.valueOf(archRow.get("status"));
                    if ("REJECTED".equals(archStatus) && archRow.get("result_json") != null) {
                        throw rejected(readResult(String.valueOf(archRow.get("result_json"))));
                    }
                    if (!"APPLIED".equals(archStatus) || archRow.get("result_json") == null) {
                        throw new KdsV2StorageException("archived command_id is not in a replayable terminal state");
                    }
                    return Claim.replay(readResult(String.valueOf(archRow.get("result_json"))), fingerprint);
                }
            } catch (KdsV2CommandConflictException | KdsV2RejectedCommandException | KdsV2StorageException ex) {
                throw ex;
            } catch (Exception ex) {
                // Archive table may not exist yet or empty
            }
            return Claim.execute(fingerprint);
        }

        Map<String, Object> row = jdbc.queryForMap(
                "SELECT request_fingerprint,status,result_json FROM t_kds_v2_command "
                        + "WHERE shop_id=? AND command_id=? FOR UPDATE",
                shopId, commandId);
        if (!fingerprint.equals(String.valueOf(row.get("request_fingerprint")))) {
            throw new KdsV2CommandConflictException(
                    "command_id was already used with different command data");
        }
        String status = String.valueOf(row.get("status"));
        if ("REJECTED".equals(status) && row.get("result_json") != null) {
            throw rejected(readResult(String.valueOf(row.get("result_json"))));
        }
        if (!"APPLIED".equals(status) || row.get("result_json") == null) {
            throw new KdsV2StorageException("command_id is not in a replayable terminal state");
        }
        return Claim.replay(readResult(String.valueOf(row.get("result_json"))), fingerprint);
    }

    public void complete(int shopId, String commandId, Map<String, Object> result) {
        try {
            int updated = jdbc.update(
                    "UPDATE t_kds_v2_command SET status='APPLIED',result_json=?,applied_at=NOW(),updated_at=NOW() "
                            + "WHERE shop_id=? AND command_id=? AND status='EXECUTING'",
                    objectMapper.writeValueAsString(result), shopId, commandId);
            if (updated != 1) {
                throw new KdsV2StorageException("KDS command ledger completion lost its active claim");
            }
        } catch (KdsV2StorageException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new KdsV2StorageException("KDS command result could not be persisted", ex);
        }
    }

    /**
     * Persists a deterministic 4xx business rejection after the command business
     * transaction has rolled back. This method is invoked through the Spring proxy,
     * so the rejection cannot be rolled back with the failed mutation.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void recordRejected(int shopId, String commandId, String actorId,
                               String actorType, String commandType,
                               String schemaVersion, Map<String, Object> request,
                               int httpStatus, int businessCode, String message) {
        validateCommandId(commandId);
        if (httpStatus < 400 || httpStatus >= 500) {
            throw new IllegalArgumentException("only deterministic 4xx rejections may be persisted");
        }
        String fingerprint = fingerprint(shopId, request);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("command_id", commandId);
        result.put("status", "REJECTED");
        result.put("http_status", httpStatus);
        result.put("code", businessCode);
        result.put("message", message != null ? message : "command rejected");
        try {
            String resultJson = objectMapper.writeValueAsString(result);
            int inserted = jdbc.update(
                    "INSERT IGNORE INTO t_kds_v2_command "
                            + "(shop_id,command_id,actor_id,actor_type,command_type,request_fingerprint,request_schema_version,status,result_json,created_at,updated_at,applied_at) "
                            + "VALUES (?,?,?,?,?,?,?,'REJECTED',?,NOW(),NOW(),NOW())",
                    shopId, commandId, actorId, actorType, commandType,
                    fingerprint, schemaVersion, resultJson);
            if (inserted == 1) return;

            Map<String, Object> row = jdbc.queryForMap(
                    "SELECT request_fingerprint,status,result_json FROM t_kds_v2_command "
                            + "WHERE shop_id=? AND command_id=? FOR UPDATE",
                    shopId, commandId);
            if (!fingerprint.equals(String.valueOf(row.get("request_fingerprint")))) {
                throw new KdsV2CommandConflictException(
                        "command_id was already used with different command data");
            }
            String storedStatus = String.valueOf(row.get("status"));
            if (!"APPLIED".equals(storedStatus) && !"REJECTED".equals(storedStatus)
                    && !"EXECUTING".equals(storedStatus)) {
                throw new KdsV2StorageException("stored KDS command has an unknown status");
            }
        } catch (IllegalArgumentException | KdsV2CommandConflictException
                 | KdsV2StorageException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new KdsV2StorageException("KDS command rejection could not be persisted", ex);
        }
    }

    /**
     * Registers a command that was executed atomically by the cashier and then
     * replicated to the cloud. The replica row starts directly in APPLIED: an
     * observable EXECUTING state would be false because the LAN mutation has
     * already committed.
     *
     * The surrounding replication transaction owns this write. A collision
     * with any other command representation is rejected and never overwrites
     * the first stable result.
     */
    public void recordReplicaApplied(int shopId, String commandId,
                                     String replicationFingerprint,
                                     Map<String, Object> result) {
        validateCommandId(commandId);
        if (replicationFingerprint == null || replicationFingerprint.trim().isEmpty()) {
            throw new IllegalArgumentException("replication fingerprint is required");
        }
        Map<String, Object> identity = new LinkedHashMap<>();
        identity.put("source", "cashier_replication");
        identity.put("replication_fingerprint", replicationFingerprint.trim());
        String fingerprint = fingerprint(shopId, identity);
        try {
            String resultJson = objectMapper.writeValueAsString(result);
            int inserted = jdbc.update(
                    "INSERT IGNORE INTO t_kds_v2_command "
                            + "(shop_id,command_id,actor_id,actor_type,command_type,request_fingerprint,request_schema_version,status,result_json,created_at,updated_at,applied_at) "
                            + "VALUES (?,?,'REPLICA','SYSTEM','LAN_SYNC',?,?,'APPLIED',?,NOW(),NOW(),NOW())",
                    shopId, commandId, fingerprint, "1.0", resultJson);
            if (inserted == 1) return;

            Map<String, Object> row = jdbc.queryForMap(
                    "SELECT request_fingerprint,status,result_json FROM t_kds_v2_command "
                            + "WHERE shop_id=? AND command_id=? FOR UPDATE",
                    shopId, commandId);
            if (!fingerprint.equals(String.valueOf(row.get("request_fingerprint")))) {
                throw new KdsV2CommandConflictException(
                        "command_id was already used with different command data");
            }
            if (!"APPLIED".equals(String.valueOf(row.get("status")))
                    || row.get("result_json") == null) {
                throw new KdsV2StorageException(
                        "replicated command_id is not in a stable terminal state");
            }
        } catch (IllegalArgumentException | KdsV2CommandConflictException
                 | KdsV2StorageException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new KdsV2StorageException(
                    "replicated KDS command result could not be persisted", ex);
        }
    }

    public Map<String, Object> resolve(int shopId, String commandId) {
        if (commandId == null || commandId.isEmpty() || commandId.length() > 128) {
            throw new IllegalArgumentException("command_id must contain 1 to 128 characters");
        }
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT status,result_json FROM t_kds_v2_command WHERE shop_id=? AND command_id=?",
                shopId, commandId);
        Map<String, Object> resolution = new LinkedHashMap<>();
        resolution.put("protocol_version", 2);
        resolution.put("command_id", commandId);
        if (rows.isEmpty()) {
            try {
                List<Map<String, Object>> archRows = jdbc.queryForList(
                        "SELECT status,result_json FROM t_kds_v2_command_archive WHERE shop_id=? AND command_id=?",
                        shopId, commandId);
                if (!archRows.isEmpty()) {
                    Map<String, Object> archRow = archRows.get(0);
                    String status = String.valueOf(archRow.get("status"));
                    resolution.put("status", status);
                    resolution.put("archived", true);
                    if ("APPLIED".equals(status) || "REJECTED".equals(status)) {
                        Object resultJson = archRow.get("result_json");
                        if (resultJson != null) {
                            resolution.put("result", readResult(String.valueOf(resultJson)));
                        }
                    }
                    return resolution;
                }
            } catch (Exception ex) {
                // Archive table may not exist yet or empty
            }
            resolution.put("status", "NOT_FOUND");
            return resolution;
        }

        Map<String, Object> row = rows.get(0);
        String status = String.valueOf(row.get("status"));
        resolution.put("status", status);
        if ("APPLIED".equals(status) || "REJECTED".equals(status)) {
            Object resultJson = row.get("result_json");
            if (resultJson == null) {
                throw new KdsV2StorageException("terminal KDS command is missing its stable result");
            }
            resolution.put("result", readResult(String.valueOf(resultJson)));
        } else if (!"EXECUTING".equals(status)) {
            throw new KdsV2StorageException("stored KDS command has an unknown status");
        }
        return resolution;
    }

    private Map<String, Object> readResult(String json) {
        try {
            return objectMapper.readValue(json, new TypeReference<Map<String, Object>>() { });
        } catch (Exception ex) {
            throw new KdsV2StorageException("stored KDS command result is invalid", ex);
        }
    }

    private KdsV2RejectedCommandException rejected(Map<String, Object> result) {
        int httpStatus = number(result.get("http_status"), 409);
        int businessCode = number(result.get("code"), 4090);
        Object rawMessage = result.get("message");
        String message = rawMessage != null ? rawMessage.toString() : "command rejected";
        return new KdsV2RejectedCommandException(
                httpStatus, businessCode, message, result);
    }

    private static int number(Object value, int fallback) {
        return value instanceof Number ? ((Number) value).intValue() : fallback;
    }

    private static void validateCommandId(String commandId) {
        if (commandId == null || commandId.isEmpty() || commandId.length() > 128) {
            throw new IllegalArgumentException(
                    "command_id must contain 1 to 128 characters");
        }
    }

    private String fingerprint(int shopId, Map<String, Object> request) {
        try {
            ObjectNode root = objectMapper.createObjectNode();
            root.put("shop_id", shopId);
            JsonNode body = objectMapper.valueToTree(request);
            if (body.isObject()) {
                body = body.deepCopy();
                ((ObjectNode) body).remove("command_id");
            }
            root.set("request", canonical(body));
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(objectMapper.writeValueAsBytes(canonical(root)));
            StringBuilder hex = new StringBuilder(64);
            for (byte value : digest) {
                hex.append(String.format("%02x", value & 0xff));
            }
            return hex.toString();
        } catch (Exception ex) {
            throw new KdsV2StorageException("KDS command fingerprint calculation failed", ex);
        }
    }

    private JsonNode canonical(JsonNode value) {
        if (value == null || value.isNull() || value.isValueNode()) return value;
        if (value.isArray()) {
            ArrayNode result = objectMapper.createArrayNode();
            for (JsonNode item : value) result.add(canonical(item));
            return result;
        }
        ObjectNode result = objectMapper.createObjectNode();
        List<String> fields = new ArrayList<>();
        Iterator<String> iterator = value.fieldNames();
        while (iterator.hasNext()) fields.add(iterator.next());
        Collections.sort(fields);
        for (String field : fields) result.set(field, canonical(value.get(field)));
        return result;
    }

    public static final class Claim {
        private final boolean execute;
        private final Map<String, Object> result;
        private final String fingerprint;

        private Claim(boolean execute, Map<String, Object> result, String fingerprint) {
            this.execute = execute;
            this.result = result;
            this.fingerprint = fingerprint;
        }

        public static Claim execute(String fingerprint) {
            return new Claim(true, null, fingerprint);
        }

        public static Claim replay(Map<String, Object> result, String fingerprint) {
            return new Claim(false, new LinkedHashMap<>(result), fingerprint);
        }

        public boolean shouldExecute() {
            return execute;
        }

        public Map<String, Object> getResult() {
            return result == null ? null : new LinkedHashMap<>(result);
        }

        public String getFingerprint() {
            return fingerprint;
        }
    }
}
