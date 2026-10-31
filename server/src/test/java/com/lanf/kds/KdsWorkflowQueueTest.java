package com.lanf.kds;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * 统一工作流队列映射（对齐 docs/kds_regression_matrix.md §2.2）。
 */
class KdsWorkflowQueueTest {

    @Test
    void normalize_defaultsToPendingCook() {
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsWorkflowQueue.normalize(null));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsWorkflowQueue.normalize(""));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsWorkflowQueue.normalize("unknown"));
    }

    @Test
    void normalize_aliases() {
        assertEquals(KdsWorkflowQueue.PENDING_PREP, KdsWorkflowQueue.normalize("prep"));
        assertEquals(KdsWorkflowQueue.PENDING_PREP, KdsWorkflowQueue.normalize("待配菜"));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsWorkflowQueue.normalize("cook"));
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsWorkflowQueue.normalize("待制作"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, KdsWorkflowQueue.normalize("serve"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, KdsWorkflowQueue.normalize("待传菜"));
        assertEquals(KdsWorkflowQueue.DONE, KdsWorkflowQueue.normalize("archived"));
        assertEquals(KdsWorkflowQueue.DONE, KdsWorkflowQueue.normalize("已完成"));
    }

    @Test
    void nextAfter_flowSequence() {
        assertEquals(KdsWorkflowQueue.PENDING_COOK, KdsWorkflowQueue.nextAfter(KdsWorkflowQueue.PENDING_PREP));
        assertEquals(KdsWorkflowQueue.READY_SERVE, KdsWorkflowQueue.nextAfter(KdsWorkflowQueue.PENDING_COOK));
        assertEquals(KdsWorkflowQueue.DONE, KdsWorkflowQueue.nextAfter(KdsWorkflowQueue.READY_SERVE));
    }
}
