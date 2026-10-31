package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.entity.R;
import com.lanf.kds.replication.KdsReplicationEventRequest;
import com.lanf.kds.replication.KdsReplicationBatchRequest;
import com.lanf.kds.replication.KdsReplicationOutcome;
import com.lanf.kds.replication.KdsReplicationPolicy;
import com.lanf.kds.replication.KdsReplicationService;
import com.lanf.util.AdminShopRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.HashSet;
import java.util.Set;

@RestController
@RequestMapping("/admin/kds/replication")
public class AdminKdsReplicationController {

    private final KdsReplicationService replicationService;

    public AdminKdsReplicationController(KdsReplicationService replicationService) {
        this.replicationService = replicationService;
    }

    @PostMapping("/events")
    public ResponseEntity<R> accept(@RequestBody(required = false) KdsReplicationEventRequest body,
                                    HttpServletRequest request) {
        KdsReplicationOutcome outcome = replicationService.accept(
                AdminShopRequest.getResolvedShopId(request), body, request);
        R response = outcome.getBusinessCode() == 0
                ? R.ok().put("data", outcome.getData())
                : R.error(outcome.getBusinessCode(), outcome.getMessage()).put("data", outcome.getData());
        return ResponseEntity.status(outcome.getHttpStatus()).body(response);
    }

    @PostMapping("/events/batch")
    public ResponseEntity<R> acceptBatch(@RequestBody(required = false) KdsReplicationBatchRequest body,
                                         HttpServletRequest request) {
        try {
            List<KdsReplicationEventRequest> events = body != null ? body.getEvents() : null;
            KdsReplicationPolicy.requireBatchSize(events != null ? events.size() : 0);
            List<Map<String, Object>> results = new ArrayList<>();
            Set<String> blockedAggregates = new HashSet<>();
            int accepted = 0;
            for (KdsReplicationEventRequest event : events) {
                KdsReplicationOutcome outcome;
                String aggregateKey = event != null ? event.getAggregateKey() : null;
                if (aggregateKey != null && blockedAggregates.contains(aggregateKey)) {
                    outcome = KdsReplicationOutcome.blocked(event.getEventId(), aggregateKey);
                } else {
                    try {
                        outcome = replicationService.accept(AdminShopRequest.getResolvedShopId(request), event, request);
                    } catch (RuntimeException ex) {
                        outcome = KdsReplicationOutcome.failure("temporary cloud failure");
                    }
                    if (aggregateKey != null && outcome.getBusinessCode() != 0) {
                        blockedAggregates.add(aggregateKey);
                    }
                }
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("event_id", event != null ? event.getEventId() : null);
                item.put("http_status", outcome.getHttpStatus());
                item.put("code", outcome.getBusinessCode());
                item.put("msg", outcome.getMessage());
                item.put("data", outcome.getData());
                results.add(item);
                if (outcome.getBusinessCode() == 0) accepted++;
            }
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("results", results);
            data.put("accepted", accepted);
            data.put("failed", events.size() - accepted);
            return ResponseEntity.ok(R.ok().put("data", data));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(R.error(4000, ex.getMessage()));
        }
    }

    @GetMapping("/dead-letters")
    public ResponseEntity<R> deadLetters(@RequestParam(defaultValue = "50") int limit, HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) return ResponseEntity.badRequest().body(R.error(4000, "X-Shop-Id is required"));
        return ResponseEntity.ok(R.ok().put("data", replicationService.deadLetters(shopId, limit)));
    }

    @PostMapping("/dead-letters/{eventId}/retry")
    @AuditLog(module = "kds", action = "admin_kds_replication_retry", target = "#p0")
    public ResponseEntity<R> retry(@PathVariable String eventId, HttpServletRequest request) {
        return outcome(replicationService.retryDeadLetter(AdminShopRequest.getResolvedShopId(request), eventId, request));
    }

    @PostMapping("/dead-letters/{eventId}/replace")
    @AuditLog(module = "kds", action = "admin_kds_replication_replace", target = "#p0")
    public ResponseEntity<R> replace(@PathVariable String eventId,
                                     @RequestBody KdsReplicationEventRequest replacement,
                                     HttpServletRequest request) {
        return outcome(replicationService.replaceDeadLetter(
                AdminShopRequest.getResolvedShopId(request), eventId, replacement, request));
    }

    @PostMapping("/dead-letters/{eventId}/discard")
    @AuditLog(module = "kds", action = "admin_kds_replication_discard", target = "#p0")
    public ResponseEntity<R> discard(@PathVariable String eventId,
                                     @RequestBody(required = false) Map<String, Object> body,
                                     HttpServletRequest request) {
        String reason = body != null && body.get("reason") != null ? String.valueOf(body.get("reason")) : null;
        return ResponseEntity.ok(R.ok().put("data", replicationService.discardDeadLetter(
                AdminShopRequest.getResolvedShopId(request), eventId, reason, request)));
    }

    private static ResponseEntity<R> outcome(KdsReplicationOutcome outcome) {
        R response = outcome.getBusinessCode() == 0
                ? R.ok().put("data", outcome.getData())
                : R.error(outcome.getBusinessCode(), outcome.getMessage()).put("data", outcome.getData());
        return ResponseEntity.status(outcome.getHttpStatus()).body(response);
    }
}
