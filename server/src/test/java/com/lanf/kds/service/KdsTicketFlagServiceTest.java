package com.lanf.kds.service;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsTicketFlagServiceTest {

    @Test
    void addDishFromPersistedFlag() {
        KdsTicket t = new KdsTicket();
        t.setAdd_dish_flag(1);
        assertTrue(KdsTicketFlagService.resolveAddDishFlag(t, new Order(), new OrderDetail()));
    }

    @Test
    void notAddDishFromOrderNumberSnapshotAlone() {
        KdsTicket t = new KdsTicket();
        t.setOrder_number_snapshot(2);
        OrderDetail d = new OrderDetail();
        d.setMorder_num(1);
        assertFalse(KdsTicketFlagService.resolveAddDishFlag(t, new Order(), d));
    }

    @Test
    void addDishLegacyFromMorderNum() {
        OrderDetail d = new OrderDetail();
        d.setMorder_num(2);
        assertTrue(KdsTicketFlagService.resolveAddDishFlag(new KdsTicket(), new Order(), d));
    }

    @Test
    void overdueFromPersistedFlag() {
        KdsTicket t = new KdsTicket();
        t.setItem_status(KdsItemStatus.PENDING);
        t.setOverdue_flag(1);
        t.setCreated_at(new Date(System.currentTimeMillis() - 60_000));
        assertTrue(KdsTicketFlagService.resolveOverdueFlag(t, 600, System.currentTimeMillis()));
    }

    @Test
    void overdueComputedWhenNotPersisted() {
        KdsTicket t = new KdsTicket();
        t.setItem_status(KdsItemStatus.PENDING);
        t.setOverdue_flag(0);
        t.setCreated_at(new Date(System.currentTimeMillis() - 700_000));
        assertTrue(KdsTicketFlagService.resolveOverdueFlag(t, 600, System.currentTimeMillis()));
    }

    @Test
    void notOverdueWhenDone() {
        KdsTicket t = new KdsTicket();
        t.setItem_status(KdsItemStatus.DONE);
        t.setOverdue_flag(1);
        assertFalse(KdsTicketFlagService.resolveOverdueFlag(t, 600, System.currentTimeMillis()));
    }

    @Test
    void schedulerUsesDishDurationInsteadOfShopSla() {
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        KdsDishServingDurationService durationService = mock(KdsDishServingDurationService.class);
        KdsTicketFlagService service = new KdsTicketFlagService();
        ReflectionTestUtils.setField(service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(service, "pushService", mock(KdsPushService.class));
        ReflectionTestUtils.setField(service, "servingDurationService", durationService);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(1L);
        ticket.setOrder_id(2);
        ticket.setDetail_id(3);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setOverdue_flag(0);
        ticket.setArchived(0);
        ticket.setCreated_at(new Date(System.currentTimeMillis() - 11 * 60_000L));
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(durationService.resolveSecondsByDetailIds(any(), anyInt(), any()))
                .thenReturn(Collections.singletonMap(3, 18 * 60));

        service.refreshOverdueForShop(7, 10 * 60);

        verify(ticketMapper, never()).updateById(any(KdsTicket.class));
    }

    @Test
    void schedulerClearsOldOverdueFlagAfterDishDurationIsExtended() {
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        KdsDishServingDurationService durationService = mock(KdsDishServingDurationService.class);
        KdsTicketFlagService service = new KdsTicketFlagService();
        ReflectionTestUtils.setField(service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(service, "pushService", mock(KdsPushService.class));
        ReflectionTestUtils.setField(service, "servingDurationService", durationService);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(4L);
        ticket.setOrder_id(5);
        ticket.setDetail_id(6);
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setOverdue_flag(1);
        ticket.setArchived(0);
        ticket.setCreated_at(new Date(System.currentTimeMillis() - 11 * 60_000L));
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(durationService.resolveSecondsByDetailIds(any(), anyInt(), any()))
                .thenReturn(Collections.singletonMap(6, 18 * 60));

        service.refreshOverdueForShop(7, 10 * 60);

        verify(ticketMapper).updateById(ticket);
        assertFalse(ticket.getOverdue_flag() == 1);
    }
}
