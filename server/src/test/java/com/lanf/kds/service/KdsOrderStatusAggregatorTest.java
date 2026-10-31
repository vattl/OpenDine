package com.lanf.kds.service;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsTicket;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class KdsOrderStatusAggregatorTest {

    @Test
    void allPending_isWaiting() {
        List<KdsTicket> tickets = Arrays.asList(ticket(KdsItemStatus.PENDING), ticket(KdsItemStatus.PENDING));
        assertEquals(KdsOrderStatus.WAITING, KdsOrderStatusAggregator.computeOrderStatus(tickets, false));
    }

    @Test
    void allDone_isAllDone() {
        List<KdsTicket> tickets = Arrays.asList(ticket(KdsItemStatus.DONE), ticket(KdsItemStatus.DONE));
        assertEquals(KdsOrderStatus.ALL_DONE, KdsOrderStatusAggregator.computeOrderStatus(tickets, false));
    }

    @Test
    void mixedDoneAndPending_isPartial() {
        List<KdsTicket> tickets = Arrays.asList(ticket(KdsItemStatus.DONE), ticket(KdsItemStatus.PENDING));
        assertEquals(KdsOrderStatus.PARTIAL, KdsOrderStatusAggregator.computeOrderStatus(tickets, false));
    }

    @Test
    void cookingOnly_isCooking() {
        List<KdsTicket> tickets = Collections.singletonList(ticket(KdsItemStatus.COOKING));
        assertEquals(KdsOrderStatus.COOKING, KdsOrderStatusAggregator.computeOrderStatus(tickets, false));
    }

    @Test
    void orderClosed_is90() {
        assertEquals(KdsOrderStatus.CLOSED, KdsOrderStatusAggregator.computeOrderStatus(null, true));
    }

    private static KdsTicket ticket(int status) {
        KdsTicket t = new KdsTicket();
        t.setItem_status(status);
        return t;
    }
}
