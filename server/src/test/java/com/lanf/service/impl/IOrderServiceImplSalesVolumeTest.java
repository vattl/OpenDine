package com.lanf.service.impl;

import com.lanf.entity.Shop;
import com.lanf.mapper.OrderMapper;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDate;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class IOrderServiceImplSalesVolumeTest {

    private IOrderServiceImpl service;
    private OrderMapper orderMapper;

    @BeforeEach
    void setUp() {
        service = new IOrderServiceImpl();
        orderMapper = mock(OrderMapper.class);
        IShopService shopService = mock(IShopService.class);
        Shop shop = new Shop();
        shop.setOpen_time("00:00");
        shop.setSettle_time("00:00");
        when(shopService.getById(7)).thenReturn(shop);
        when(orderMapper.getSalesVolumeByEveningPeriod(any(), any(), any(), any(), any(), any()))
                .thenReturn(Collections.emptyList());
        ReflectionTestUtils.setField(service, "orderMapper", orderMapper);
        ReflectionTestUtils.setField(service, "shopService", shopService);
    }

    @Test
    void dayWithoutDateUsesCurrentOperationalWindowEndingAtNextSettlement() {
        service.getSalesVolumeByEveningPeriod("day", 7, null, null);

        ArgumentCaptor<String> settlementDate = ArgumentCaptor.forClass(String.class);
        verify(orderMapper).getSalesVolumeByEveningPeriod(
                eq("day"), eq(7), eq(null), eq("00:00"), eq("00:00"), settlementDate.capture());
        assertEquals(LocalDate.now().plusDays(1).toString(), settlementDate.getValue());
    }

    @Test
    void explicitSettlementDateKeepsHistoricalWindowSemantics() {
        service.getSalesVolumeByEveningPeriod("day", 7, null, "2026-09-30");

        verify(orderMapper).getSalesVolumeByEveningPeriod(
                "day", 7, null, "00:00", "00:00", "2026-09-30");
    }
}
