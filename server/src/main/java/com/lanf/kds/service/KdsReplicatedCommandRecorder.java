package com.lanf.kds.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Bridges an already-applied cashier command into the cloud KDS command ledger
 * and persistent change stream. The caller must own a database transaction.
 */
@Service
public class KdsReplicatedCommandRecorder {

    private final KdsV2CommandLedger commandLedger;
    private final KdsV2EventStore eventStore;
    private final KdsOverviewBoardService overviewBoardService;
    private final ObjectMapper objectMapper;

    public KdsReplicatedCommandRecorder(KdsV2CommandLedger commandLedger,
                                        KdsV2EventStore eventStore,
                                        KdsOverviewBoardService overviewBoardService,
                                        ObjectMapper objectMapper) {
        this.commandLedger = commandLedger;
        this.eventStore = eventStore;
        this.overviewBoardService = overviewBoardService;
        this.objectMapper = objectMapper;
    }

    public Map<String, Object> recordApplied(int shopId,
                                             String commandId,
                                             String replicationFingerprint,
                                             String operationType,
                                             long occurredAtMs,
                                             JsonNode lines) {
        if (lines == null || !lines.isArray() || lines.size() == 0) {
            throw new IllegalArgumentException("replicated KDS command lines are required");
        }
        List<Map<String, Object>> patches = new ArrayList<>();
        for (JsonNode lineNode : lines) {
            Map<String, Object> line = objectMapper.convertValue(
                    lineNode, new TypeReference<Map<String, Object>>() { });
            Object detailId = line.get("detail_id");
            if (!(detailId instanceof Number)
                    || ((Number) detailId).longValue() <= 0) {
                throw new IllegalArgumentException(
                        "replicated KDS command line requires a formal detail_id");
            }
            boolean removed = Boolean.TRUE.equals(line.get("removed"));
            Map<String, Object> patch = new LinkedHashMap<>();
            patch.put("detail_id", detailId);
            patch.put("removed", removed);
            if (!removed) patch.put("line", line);
            patches.add(patch);
        }

        long eventSequence = eventStore.nextSequence(shopId);
        Map<String, Integer> queueCounts = overviewBoardService
                .countWorkflowQueues(shopId, "all", null, null);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("command_id", commandId);
        result.put("duplicate", false);
        result.put("event_seq", eventSequence);
        result.put("patches", patches);
        result.put("queue_counts", queueCounts);

        commandLedger.recordReplicaApplied(
                shopId, commandId, replicationFingerprint, result);

        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("protocol_version", 2);
        envelope.put("event_seq", eventSequence);
        envelope.put("event_id", "cmd:" + commandId);
        envelope.put("type", operationType);
        envelope.put("shop_id", shopId);
        envelope.put("occurred_at_ms", occurredAtMs);
        envelope.put("patches", patches);
        envelope.put("queue_counts", queueCounts);
        eventStore.append(shopId, envelope);
        return result;
    }
}
