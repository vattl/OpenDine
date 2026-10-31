package com.lanf.kds.support;

import com.lanf.entity.Order;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsOrderCompletionSyncTest {

    @Test
    void recOrder_shouldMark() {
        Order o = new Order();
        o.setOrder_receiving("rec_order");
        o.setTransac_status("unsettled");
        assertTrue(KdsOrderCompletionSync.shouldMarkOffOrder(o));
    }

    @Test
    void alreadyOffOrder_shouldNotMark() {
        Order o = new Order();
        o.setOrder_receiving("off_order");
        assertFalse(KdsOrderCompletionSync.shouldMarkOffOrder(o));
    }

    @Test
    void cancelled_shouldNotMark() {
        Order o = new Order();
        o.setOrder_receiving("rec_order");
        o.setTransac_status("cancelled");
        assertFalse(KdsOrderCompletionSync.shouldMarkOffOrder(o));
    }

    @Test
    void misOrder_shouldNotMark() {
        Order o = new Order();
        o.setOrder_receiving("mis_order");
        assertFalse(KdsOrderCompletionSync.shouldMarkOffOrder(o));
    }
}
