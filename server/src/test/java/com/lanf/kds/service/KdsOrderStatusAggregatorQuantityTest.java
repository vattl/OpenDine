package com.lanf.kds.service;

import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsTicket;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * 整单状态聚合 — 数量维度（computeByQuantity 分支）。
 * 对齐 docs/kds_meituan_alignment.md「订单状态」：有数量进度时按已传份数/总份数推导。
 */
class KdsOrderStatusAggregatorQuantityTest {

    @Test
    void noQuantityProgress_fallsBackToItemStatus() {
        // 无 prep/cooked/served 数量 → 回退 item_status 统计（全 PENDING → WAITING）
        List<KdsTicket> tickets = Collections.singletonList(ticket(1, 0, null, 0, null));
        assertEquals(KdsOrderStatus.WAITING,
                KdsOrderStatusAggregator.computeOrderStatus(tickets, false, details(1, 2)));
    }

    @Test
    void partialServed_isPartial() {
        // line=4, served=2 → 部分出餐
        List<KdsTicket> tickets = Collections.singletonList(ticket(1, 4, 4, 2, null));
        assertEquals(KdsOrderStatus.PARTIAL,
                KdsOrderStatusAggregator.computeOrderStatus(tickets, false, details(1, 4)));
    }

    @Test
    void fullyServed_isAllDone() {
        // line=4, served=4 → 整单完成
        List<KdsTicket> tickets = Collections.singletonList(ticket(1, 4, 4, 4, null));
        assertEquals(KdsOrderStatus.ALL_DONE,
                KdsOrderStatusAggregator.computeOrderStatus(tickets, false, details(1, 4)));
    }

    @Test
    void progressNoServed_isCooking() {
        // 有 prep/cooked 进度但 served=0 → 制作中
        List<KdsTicket> tickets = Collections.singletonList(ticket(1, 4, 2, 0, null));
        assertEquals(KdsOrderStatus.COOKING,
                KdsOrderStatusAggregator.computeOrderStatus(tickets, false, details(1, 4)));
    }

    @Test
    void cookedQuantityFallbackFromDoneStatus() {
        // cooked_quantity=null 且无 prep/served 进度 → hasQuantityProgress=false → 回退 item_status；
        // 单条 DONE → done==total → ALL_DONE
        List<KdsTicket> tickets = Collections.singletonList(ticket(1, 0, null, 0, 2)); // status=DONE
        assertEquals(KdsOrderStatus.ALL_DONE,
                KdsOrderStatusAggregator.computeOrderStatus(tickets, false, details(1, 3)));
    }

    private static KdsTicket ticket(int detailId, int prep, Integer cooked, int served, Integer itemStatus) {
        KdsTicket t = new KdsTicket();
        t.setDetail_id(detailId);
        t.setPrep_quantity(prep);
        t.setCooked_quantity(cooked);
        t.setServed_quantity(served);
        t.setItem_status(itemStatus);
        return t;
    }

    private static Map<Integer, OrderDetail> details(int detailId, int lineQty) {
        OrderDetail d = new OrderDetail();
        d.setId(detailId);
        d.setQuantity(String.valueOf(lineQty));
        Map<Integer, OrderDetail> m = new HashMap<>();
        m.put(detailId, d);
        return m;
    }

    @Test
    void multiTicket_mixedProgress() {
        // 两条明细：一条全传完、一条未动 → 部分出餐
        KdsTicket done = ticket(1, 2, 2, 2, null);
        KdsTicket fresh = ticket(2, 0, null, 0, null);
        Map<Integer, OrderDetail> details = new HashMap<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(1);
        d1.setQuantity("2");
        OrderDetail d2 = new OrderDetail();
        d2.setId(2);
        d2.setQuantity("3");
        details.put(1, d1);
        details.put(2, d2);
        assertEquals(KdsOrderStatus.PARTIAL,
                KdsOrderStatusAggregator.computeOrderStatus(Arrays.asList(done, fresh), false, details));
    }
}
