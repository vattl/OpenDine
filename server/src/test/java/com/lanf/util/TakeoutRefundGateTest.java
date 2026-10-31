package com.lanf.util;

import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TakeoutRefundGateTest {

    @Test
    void nonTakeoutOrderAlwaysAllowed() {
        Order order = new Order();
        order.setDineInOrTakeOut("堂食");
        assertNull(TakeoutRefundGate.blockReason(order, null));
    }

    @Test
    void takeoutWithoutDeliveryBlocked() {
        Order order = new Order();
        order.setDineInOrTakeOut("外卖");
        assertEquals("外卖订单缺少配送记录，无法退款", TakeoutRefundGate.blockReason(order, null));
    }

    @Test
    void takeoutNotDispatchedYetAllowed() {
        Order order = new Order();
        order.setDineInOrTakeOut("外卖");
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("accepted");
        assertNull(TakeoutRefundGate.blockReason(order, d));
    }

    @Test
    void takeoutDispatchedButNotCompletedBlocked() {
        Order order = new Order();
        order.setDineInOrTakeOut("外卖");
        TakeoutDelivery d = new TakeoutDelivery();
        d.setZsq_open_order_id(100L);
        d.setDispatch_status("delivering");
        String msg = TakeoutRefundGate.blockReason(order, d);
        assertTrue(msg != null && msg.contains("须配送完成后方可退款"));
    }

    @Test
    void takeoutCompletedAllowed() {
        Order order = new Order();
        order.setDineInOrTakeOut("外卖");
        TakeoutDelivery d = new TakeoutDelivery();
        d.setZsq_open_order_id(100L);
        d.setDispatch_status("completed");
        assertNull(TakeoutRefundGate.blockReason(order, d));
    }
}
