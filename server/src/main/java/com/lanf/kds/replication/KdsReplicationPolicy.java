package com.lanf.kds.replication;

import java.util.Locale;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.List;

public final class KdsReplicationPolicy {

    public static final String ORDER_CREATED = "order_created";
    public static final String KDS_ADVANCE_ITEM = "kds_advance_item";
    public static final String KDS_STATE_CHANGED = "kds_state_changed";
    public static final int MAX_BATCH_SIZE = 50;
    private static final Set<String> OPERATION_TYPES = new HashSet<>(Arrays.asList(
            "advance_item", "advance_order", "revoke_item", "lack_item", "refund_item",
            "rush_item", "rush_order", "hold_item", "release_item", "complete_order",
            "archive_order", "archive_clear"));

    private KdsReplicationPolicy() {
    }

    public static boolean isSupportedType(String eventType) {
        String normalized = normalizeEventType(eventType);
        return ORDER_CREATED.equals(normalized) || KDS_ADVANCE_ITEM.equals(normalized)
                || KDS_STATE_CHANGED.equals(normalized);
    }

    public static void requireBatchSize(int size) {
        if (size < 1 || size > MAX_BATCH_SIZE) {
            throw new IllegalArgumentException("events must contain between 1 and 50 items");
        }
    }

    public static void requireOperationType(String operationType) {
        if (operationType == null || !OPERATION_TYPES.contains(operationType.trim().toLowerCase(Locale.ROOT))) {
            throw new IllegalArgumentException("unsupported operation_type");
        }
    }

    public static void requireCompleteDetailSet(Set<Long> mappedDetailIds, List<Long> incomingDetailIds) {
        if (mappedDetailIds == null || incomingDetailIds == null) {
            throw new IllegalArgumentException("mapped and incoming detail ids are required");
        }
        Set<Long> incoming = new HashSet<>(incomingDetailIds);
        if (incoming.size() != incomingDetailIds.size()) {
            throw new IllegalArgumentException("lines must not contain duplicate local_detail_id values");
        }
        if (!incoming.equals(mappedDetailIds)) {
            throw new IllegalArgumentException("lines must completely and exclusively cover mapped order details");
        }
    }

    public static String normalizeEventType(String eventType) {
        return eventType == null ? "" : eventType.trim().toLowerCase(Locale.ROOT);
    }

    public static long localOrderId(String aggregateKey) {
        if (aggregateKey == null || !aggregateKey.matches("order:[1-9]\\d*")) {
            throw new IllegalArgumentException("aggregate_key must be order:<positive local order id>");
        }
        try {
            return Long.parseLong(aggregateKey.substring("order:".length()));
        } catch (NumberFormatException ex) {
            throw new IllegalArgumentException("aggregate_key local order id is invalid", ex);
        }
    }

    public static void requireAggregateOrder(String aggregateKey, long payloadLocalOrderId) {
        if (localOrderId(aggregateKey) != payloadLocalOrderId) {
            throw new IllegalArgumentException("aggregate_key and payload local order id do not match");
        }
    }

    public static RevisionDecision revisionDecision(Long currentRevision, Long incomingRevision) {
        if (incomingRevision == null || incomingRevision <= 0) {
            throw new IllegalArgumentException("local_revision must be a positive integer");
        }
        return currentRevision == null || incomingRevision > currentRevision
                ? RevisionDecision.APPLY
                : RevisionDecision.IGNORE_OLD;
    }

    public static int refundDelta(int previousCumulative, int incomingCumulative) {
        if (previousCumulative < 0 || incomingCumulative < 0) {
            throw new IllegalArgumentException("refunded quantities must be non-negative");
        }
        return Math.max(0, incomingCumulative - previousCumulative);
    }

    public static LineProgress lineProgress(int quantity, int prepRemaining, int cookRemaining,
                                            int readyRemaining, boolean doneLine) {
        if (quantity < 0 || prepRemaining < 0 || cookRemaining < 0 || readyRemaining < 0
                || prepRemaining > quantity || cookRemaining > quantity || readyRemaining > quantity) {
            throw new IllegalArgumentException("remaining quantities must be between 0 and line quantity");
        }
        if (doneLine) {
            return new LineProgress(quantity, quantity, quantity);
        }
        int prep = quantity - prepRemaining;
        int cooked = quantity - cookRemaining;
        int served = quantity - readyRemaining;
        if (served > cooked || cooked > prep) {
            throw new IllegalArgumentException("remaining quantities must preserve prep >= cooked >= served");
        }
        return new LineProgress(prep, cooked, served);
    }

    public static final class LineProgress {
        private final int prep;
        private final int cooked;
        private final int served;

        private LineProgress(int prep, int cooked, int served) {
            this.prep = prep;
            this.cooked = cooked;
            this.served = served;
        }

        public int getPrep() {
            return prep;
        }

        public int getCooked() {
            return cooked;
        }

        public int getServed() {
            return served;
        }
    }

    public static boolean hasMonotonicProgress(int currentPrep, int currentCooked, int currentServed,
                                               int incomingPrep, int incomingCooked, int incomingServed) {
        return incomingPrep > currentPrep || incomingCooked > currentCooked || incomingServed > currentServed;
    }

    public enum RevisionDecision {
        APPLY,
        IGNORE_OLD,
        CONFLICT_FORK
    }
}
