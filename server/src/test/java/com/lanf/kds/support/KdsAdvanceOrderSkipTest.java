package com.lanf.kds.support;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsTicket;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 整单推进应跳过本 Tab 已划完明细（docs/backend_order_view_coordination.md）。
 */
class KdsAdvanceOrderSkipTest {

    @Test
    void pendingCook_skipFullyCookedLine() {
        KdsTicket t = ticket(3, 3, 0);
        assertFalse(KdsTicketQuantityUtil.hasQueueWork(t, 3, KdsWorkflowQueue.PENDING_COOK));
        assertEquals(0, KdsTicketQuantityUtil.displayQuantity(t, 3, KdsWorkflowQueue.PENDING_COOK));
    }

    @Test
    void pendingCook_advancePartiallyCookedOnly() {
        KdsTicket t = ticket(3, 1, 0);
        assertTrue(KdsTicketQuantityUtil.hasQueueWork(t, 3, KdsWorkflowQueue.PENDING_COOK));
        assertEquals(2, KdsTicketQuantityUtil.displayQuantity(t, 3, KdsWorkflowQueue.PENDING_COOK));
    }

    private static KdsTicket ticket(int lineQty, int cooked, int served) {
        KdsTicket t = new KdsTicket();
        t.setItem_status(KdsItemStatus.PENDING);
        t.setArchived(0);
        t.setPrep_quantity(lineQty);
        t.setCooked_quantity(cooked);
        t.setServed_quantity(served);
        return t;
    }
}
