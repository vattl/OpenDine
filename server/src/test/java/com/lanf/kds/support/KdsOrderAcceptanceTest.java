package com.lanf.kds.support;

import com.lanf.entity.Order;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsOrderAcceptanceTest {

    @Test
    void acceptedWhenRecOrder() {
        Order o = new Order();
        o.setOrder_receiving("rec_order");
        assertTrue(KdsOrderAcceptance.isAccepted(o));
    }

    @Test
    void notAcceptedWhenMisOrder() {
        Order o = new Order();
        o.setOrder_receiving("mis_order");
        assertFalse(KdsOrderAcceptance.isAccepted(o));
    }

    @Test
    void notAcceptedWhenNull() {
        assertFalse(KdsOrderAcceptance.isAccepted(null));
        assertFalse(KdsOrderAcceptance.isAccepted(new Order()));
    }

    @Test
    void dineInOrderStillRequiresReceiptAcceptance() {
        Order order = new Order();
        order.setDineInOrTakeOut("堂食");
        order.setOrder_receiving("mis_order");

        assertFalse(KdsOrderAcceptance.isAccepted(order));
    }
}
