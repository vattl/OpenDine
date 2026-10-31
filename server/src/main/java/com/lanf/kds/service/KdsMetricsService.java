package com.lanf.kds.service;

import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.LongAdder;

/**
 * KDS 商用度量指标收集服务：
 * 线程安全地收集与计算命令执行质量、WebSocket 实时性与丢包/慢消费断链、以及快照与增量查询分布。
 */
@Service
public class KdsMetricsService {

    private final long startedAtMs = System.currentTimeMillis();

    // Command metrics
    private final LongAdder totalCommands = new LongAdder();
    private final LongAdder successCommands = new LongAdder();
    private final LongAdder conflictCommands = new LongAdder(); // 409
    private final LongAdder rejectedCommands = new LongAdder(); // 400
    private final LongAdder errorCommands = new LongAdder();    // 500+
    private final LongAdder totalCommandDurationMs = new LongAdder();
    private final AtomicLong maxCommandDurationMs = new AtomicLong(0);
    private final AtomicLong minCommandDurationMs = new AtomicLong(Long.MAX_VALUE);

    // Sliding window for latency p95 approximation (keep recent 1000 samples)
    private final ConcurrentLinkedQueue<Long> recentCommandLatencies = new ConcurrentLinkedQueue<>();
    private static final int MAX_LATENCY_SAMPLES = 1000;

    // WebSocket metrics
    private final LongAdder wsDispatchedFrames = new LongAdder();
    private final LongAdder wsAcknowledgedFrames = new LongAdder();
    private final ConcurrentHashMap<String, LongAdder> wsDisconnectReasons = new ConcurrentHashMap<>();

    // Traffic / Poll metrics
    private final LongAdder bootstrapRequests = new LongAdder();
    private final LongAdder businessDayRequests = new LongAdder();
    private final LongAdder changesRequests = new LongAdder();

    public void recordCommandExecution(int shopId, String commandType, int httpStatus, long durationMs) {
        totalCommands.increment();
        totalCommandDurationMs.add(durationMs);

        // Update max
        maxCommandDurationMs.accumulateAndGet(durationMs, Math::max);
        // Update min
        minCommandDurationMs.accumulateAndGet(durationMs, Math::min);

        // Maintain sliding latency sample
        recentCommandLatencies.add(durationMs);
        while (recentCommandLatencies.size() > MAX_LATENCY_SAMPLES) {
            recentCommandLatencies.poll();
        }

        if (httpStatus >= 200 && httpStatus < 300) {
            successCommands.increment();
        } else if (httpStatus == 409) {
            conflictCommands.increment();
        } else if (httpStatus == 400) {
            rejectedCommands.increment();
        } else if (httpStatus >= 500) {
            errorCommands.increment();
        }
    }

    public void recordBootstrapRequest(int shopId) {
        bootstrapRequests.increment();
    }

    public void recordBusinessDayRequest(int shopId) {
        businessDayRequests.increment();
    }

    public void recordChangesRequest(int shopId) {
        changesRequests.increment();
    }

    public void recordWsDispatched(int count) {
        wsDispatchedFrames.add(count);
    }

    public void recordWsAcknowledged() {
        wsAcknowledgedFrames.increment();
    }

    public void recordWsDisconnect(String reason) {
        if (reason == null || reason.trim().isEmpty()) {
            reason = "unknown";
        }
        wsDisconnectReasons.computeIfAbsent(reason, k -> new LongAdder()).increment();
    }

    public Map<String, Object> getMetricsSnapshot() {
        Map<String, Object> snapshot = new HashMap<>();
        long now = System.currentTimeMillis();
        snapshot.put("uptime_seconds", Math.max(0, (now - startedAtMs) / 1000));
        snapshot.put("started_at_ms", startedAtMs);
        snapshot.put("timestamp_ms", now);

        // Command stats
        long totalCmd = totalCommands.sum();
        long successCmd = successCommands.sum();
        long conflictCmd = conflictCommands.sum();
        long rejectedCmd = rejectedCommands.sum();
        long errorCmd = errorCommands.sum();
        long totalDuration = totalCommandDurationMs.sum();

        Map<String, Object> commandStats = new HashMap<>();
        commandStats.put("total_count", totalCmd);
        commandStats.put("success_count", successCmd);
        commandStats.put("conflict_count", conflictCmd);
        commandStats.put("rejected_count", rejectedCmd);
        commandStats.put("error_count", errorCmd);

        double conflictRate = totalCmd > 0 ? (double) conflictCmd / totalCmd : 0.0;
        double rejectionRate = totalCmd > 0 ? (double) rejectedCmd / totalCmd : 0.0;
        commandStats.put("conflict_rate", Math.round(conflictRate * 10000.0) / 10000.0);
        commandStats.put("rejection_rate", Math.round(rejectionRate * 10000.0) / 10000.0);

        Map<String, Object> latencyStats = new HashMap<>();
        latencyStats.put("avg_ms", totalCmd > 0 ? (double) totalDuration / totalCmd : 0.0);
        latencyStats.put("max_ms", maxCommandDurationMs.get());
        long minVal = minCommandDurationMs.get();
        latencyStats.put("min_ms", minVal == Long.MAX_VALUE ? 0 : minVal);

        // Calculate p95 from recent sample
        List<Long> samples = new ArrayList<>(recentCommandLatencies);
        if (!samples.isEmpty()) {
            Collections.sort(samples);
            int p95Index = (int) Math.ceil(samples.size() * 0.95) - 1;
            p95Index = Math.max(0, Math.min(p95Index, samples.size() - 1));
            latencyStats.put("p95_ms", samples.get(p95Index));
        } else {
            latencyStats.put("p95_ms", 0);
        }
        commandStats.put("latency", latencyStats);
        snapshot.put("commands", commandStats);

        // WebSocket stats
        long wsSent = wsDispatchedFrames.sum();
        long wsAcked = wsAcknowledgedFrames.sum();
        Map<String, Object> wsStats = new HashMap<>();
        wsStats.put("dispatched_frames", wsSent);
        wsStats.put("acknowledged_frames", wsAcked);
        double ackRate = wsSent > 0 ? (double) wsAcked / wsSent : 1.0;
        wsStats.put("ack_rate", Math.round(ackRate * 10000.0) / 10000.0);

        Map<String, Long> disconnects = new HashMap<>();
        wsDisconnectReasons.forEach((k, v) -> disconnects.put(k, v.sum()));
        wsStats.put("disconnect_reasons", disconnects);
        snapshot.put("websocket", wsStats);

        // Traffic / Polling stats
        long bootstrapCount = bootstrapRequests.sum();
        long businessDayCount = businessDayRequests.sum();
        long changesCount = changesRequests.sum();
        Map<String, Object> trafficStats = new HashMap<>();
        trafficStats.put("bootstrap_requests", bootstrapCount);
        trafficStats.put("business_day_requests", businessDayCount);
        trafficStats.put("changes_requests", changesCount);
        long totalSnapshots = bootstrapCount + businessDayCount;
        double snapshotRatio = changesCount > 0 ? (double) totalSnapshots / changesCount : totalSnapshots;
        trafficStats.put("snapshot_to_changes_ratio", Math.round(snapshotRatio * 10000.0) / 10000.0);
        snapshot.put("traffic", trafficStats);

        return snapshot;
    }

    public void reset() {
        totalCommands.reset();
        successCommands.reset();
        conflictCommands.reset();
        rejectedCommands.reset();
        errorCommands.reset();
        totalCommandDurationMs.reset();
        maxCommandDurationMs.set(0);
        minCommandDurationMs.set(Long.MAX_VALUE);
        recentCommandLatencies.clear();
        wsDispatchedFrames.reset();
        wsAcknowledgedFrames.reset();
        wsDisconnectReasons.clear();
        bootstrapRequests.reset();
        businessDayRequests.reset();
        changesRequests.reset();
    }
}
