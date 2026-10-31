package com.lanf.kds.replication;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;
import java.util.Arrays;
import java.util.HashSet;

class KdsReplicationPolicyTest {
    @Test
    void cumulativeRefundProducesOnlyNewDomainInventoryRestoreDelta() {
        assertEquals(2, KdsReplicationPolicy.refundDelta(1, 3));
        assertEquals(0, KdsReplicationPolicy.refundDelta(3, 3));
        assertEquals(0, KdsReplicationPolicy.refundDelta(3, 2));
    }

    @Test
    void onlyImplementedEventTypesAreAccepted() {
        assertTrue(KdsReplicationPolicy.isSupportedType("order_created"));
        assertTrue(KdsReplicationPolicy.isSupportedType(" KDS_ADVANCE_ITEM "));
        assertTrue(KdsReplicationPolicy.isSupportedType("kds_state_changed"));
        assertFalse(KdsReplicationPolicy.isSupportedType("order_refunded"));
        assertFalse(KdsReplicationPolicy.isSupportedType(null));
    }

    @Test
    void batchSizeIsBoundedForPredictableCloudLoad() {
        assertEquals(50, KdsReplicationPolicy.MAX_BATCH_SIZE);
        assertDoesNotThrow(() -> KdsReplicationPolicy.requireBatchSize(50));
        assertThrows(IllegalArgumentException.class, () -> KdsReplicationPolicy.requireBatchSize(0));
        assertThrows(IllegalArgumentException.class, () -> KdsReplicationPolicy.requireBatchSize(51));
    }

    @Test
    void aggregateKeyMustContainTheSameLocalOrder() {
        assertEquals(37L, KdsReplicationPolicy.localOrderId("order:37"));
        assertThrows(IllegalArgumentException.class,
                () -> KdsReplicationPolicy.requireAggregateOrder("order:38", 37L));
        assertThrows(IllegalArgumentException.class,
                () -> KdsReplicationPolicy.localOrderId("shop:37"));
    }

    @Test
    void revisionsAreMonotonicPerLocalDetail() {
        assertEquals(KdsReplicationPolicy.RevisionDecision.APPLY,
                KdsReplicationPolicy.revisionDecision(2L, 3L));
        assertEquals(KdsReplicationPolicy.RevisionDecision.IGNORE_OLD,
                KdsReplicationPolicy.revisionDecision(3L, 3L));
        assertEquals(KdsReplicationPolicy.RevisionDecision.IGNORE_OLD,
                KdsReplicationPolicy.revisionDecision(5L, 4L));
    }

    @Test
    void remainingQuantitiesRestoreCumulativeProgress() {
        KdsReplicationPolicy.LineProgress progress = KdsReplicationPolicy.lineProgress(2, 0, 2, 2, false);
        assertEquals(2, progress.getPrep());
        assertEquals(0, progress.getCooked());
        assertEquals(0, progress.getServed());

        KdsReplicationPolicy.LineProgress done = KdsReplicationPolicy.lineProgress(2, 2, 2, 2, true);
        assertEquals(2, done.getPrep());
        assertEquals(2, done.getCooked());
        assertEquals(2, done.getServed());
        assertThrows(IllegalArgumentException.class,
                () -> KdsReplicationPolicy.lineProgress(2, 1, 0, 2, false));
    }

    @Test
    void fullSnapshotMustExactlyCoverMappedDetailsWithoutDuplicates() {
        HashSet<Long> mapped = new HashSet<>(Arrays.asList(11L, 12L));
        assertDoesNotThrow(() -> KdsReplicationPolicy.requireCompleteDetailSet(mapped, Arrays.asList(11L, 12L)));
        assertThrows(IllegalArgumentException.class,
                () -> KdsReplicationPolicy.requireCompleteDetailSet(mapped, Arrays.asList(11L)));
        assertThrows(IllegalArgumentException.class,
                () -> KdsReplicationPolicy.requireCompleteDetailSet(mapped, Arrays.asList(11L, 12L, 13L)));
        assertThrows(IllegalArgumentException.class,
                () -> KdsReplicationPolicy.requireCompleteDetailSet(mapped, Arrays.asList(11L, 11L)));
    }
}
