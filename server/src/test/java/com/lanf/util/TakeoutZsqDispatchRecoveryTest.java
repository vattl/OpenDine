package com.lanf.util;

import com.lanf.entity.TakeoutDelivery;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TakeoutZsqDispatchRecoveryTest {

    @Test
    void preparePreservesCancelledOpenOrderForRedispatch() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("cancelled");
        d.setZsq_dispatch_status("cancelled");
        d.setZsq_open_order_id(999L);
        d.setZsq_order_id("order-999");
        d.setZsq_parent_order_no("parent-old");
        d.setMerchant_remark("请尽快配送;ZSQ取消:运营取消配送");
        d.setZsq_actual_fee(new BigDecimal("6.13"));
        d.setZsq_delivery_supplier_name("京东特惠");
        TakeoutZsqDispatchRecovery.prepareLocalForRedispatch(d);
        assertEquals(999L, d.getZsq_open_order_id());
        assertEquals("order-999", d.getZsq_order_id());
        assertNull(d.getZsq_parent_order_no());
        assertNull(d.getZsq_actual_fee());
        assertNull(d.getZsq_delivery_supplier_name());
        assertEquals("accepted", d.getDispatch_status());
        assertEquals("none", d.getZsq_dispatch_status());
        assertEquals("请尽快配送", d.getMerchant_remark());
        assertFalse(TakeoutZsqDispatchRecovery.hasOperatorCancelLock(d));
    }

    @Test
    void prepareClearsMissingRemoteOrderForFreshRedispatch() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("dispatch_failed");
        d.setZsq_dispatch_status("order_missing");
        d.setZsq_phase("ORDER_MISSING");
        d.setZsq_open_order_id(999L);
        d.setZsq_parent_order_no("deleted-parent");
        d.setZsq_last_error("真省钱配送订单不存在或已删除，可重新下单配送");
        d.setZsq_delivery_send_status(40);
        d.setZsq_rider_name("上一单骑手");
        d.setZsq_rider_phone("13800138000");
        d.setZsq_rider_lat(new BigDecimal("22.7718"));
        d.setZsq_rider_lng(new BigDecimal("112.9807"));
        d.setZsq_rider_updated_at(new Date());

        TakeoutZsqDispatchRecovery.prepareLocalForRedispatch(d);

        assertNull(d.getZsq_open_order_id());
        assertNull(d.getZsq_parent_order_no());
        assertEquals("accepted", d.getDispatch_status());
        assertEquals("none", d.getZsq_dispatch_status());
        assertNull(d.getZsq_last_error());
        assertNull(d.getZsq_delivery_send_status());
        assertNull(d.getZsq_rider_name());
        assertNull(d.getZsq_rider_phone());
        assertNull(d.getZsq_rider_lat());
        assertNull(d.getZsq_rider_lng());
        assertNull(d.getZsq_rider_updated_at());
    }

    @Test
    void preparePreservesCompletedOpenOrderForRedispatch() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("completed");
        d.setZsq_dispatch_status("completed");
        d.setZsq_phase("DELIVERED");
        d.setZsq_open_order_id(999L);
        d.setZsq_parent_order_no("completed-parent");
        d.setZsq_rider_name("旧骑手");
        d.setZsq_rider_phone("13800138000");

        TakeoutZsqDispatchRecovery.prepareLocalForRedispatch(d);

        assertEquals(999L, d.getZsq_open_order_id());
        assertNull(d.getZsq_parent_order_no());
        assertNull(d.getZsq_rider_name());
        assertNull(d.getZsq_rider_phone());
        assertNull(d.getZsq_phase());
        assertEquals("accepted", d.getDispatch_status());
        assertEquals("none", d.getZsq_dispatch_status());
    }

    @Test
    void preparePreservesOpenOrderAfterRiderCancellation() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("dispatch_failed");
        d.setZsq_dispatch_status("rider_cancelled");
        d.setZsq_open_order_id(999L);
        d.setZsq_parent_order_no("cancelled-delivery-parent");

        TakeoutZsqDispatchRecovery.prepareLocalForRedispatch(d);

        assertEquals(999L, d.getZsq_open_order_id());
        assertNull(d.getZsq_parent_order_no());
        assertEquals("accepted", d.getDispatch_status());
        assertEquals("none", d.getZsq_dispatch_status());
    }

    @Test
    void shouldRecoverWhenZsqPhaseActiveWithoutOperatorCancel() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("cancelled");
        d.setZsq_dispatch_status("cancelled");
        assertTrue(TakeoutZsqDispatchRecovery.shouldRecoverFromActiveZsqPhase(d, "WAITING_RIDER"));
    }

    @Test
    void shouldNotRecoverAfterOperatorCancel() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("cancelled");
        d.setZsq_dispatch_status("cancelled");
        d.setMerchant_remark("ZSQ取消:运营取消配送");
        assertTrue(TakeoutZsqDispatchRecovery.hasOperatorCancelLock(d));
        assertFalse(TakeoutZsqDispatchRecovery.shouldRecoverFromActiveZsqPhase(d, "WAITING_RIDER"));
    }

    @Test
    void finalizeOperatorCancelSetsAllFields() {
        TakeoutDelivery d = new TakeoutDelivery();
        d.setDispatch_status("accepted");
        d.setZsq_dispatch_status("pending");
        d.setZsq_phase("WAITING_RIDER");
        d.setZsq_last_error("err");
        TakeoutZsqDispatchRecovery.finalizeOperatorCancel(d);
        assertEquals("cancelled", d.getDispatch_status());
        assertEquals("cancelled", d.getZsq_dispatch_status());
        assertEquals("CANCELLED", d.getZsq_phase());
        assertNull(d.getZsq_last_error());
    }

    @Test
    void appendCancelRemarkOnce() {
        TakeoutDelivery d = new TakeoutDelivery();
        TakeoutZsqDispatchRecovery.appendCancelRemark(d, "运营取消配送");
        assertEquals("ZSQ取消:运营取消配送", d.getMerchant_remark());
        TakeoutZsqDispatchRecovery.appendCancelRemark(d, "运营取消配送");
        assertEquals("ZSQ取消:运营取消配送", d.getMerchant_remark());
    }
}
