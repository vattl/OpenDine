package com.lanf.kds.service;

import com.lanf.entity.Order;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsLegacySyncServiceTest {

    @Test
    void allDoneDoesNotClearTableWhenAutoOffIsDisabled() {
        KdsLegacySyncService service = new KdsLegacySyncService();
        KdsConfigService configService = mock(KdsConfigService.class);
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(service, "configService", configService);
        ReflectionTestUtils.setField(service, "orderDetailService", mock(IOrderDetailService.class));
        ReflectionTestUtils.setField(service, "orderService", orderService);

        Order order = new Order();
        order.setId(100);
        order.setOrder_no("NO100");
        order.setOrder_receiving("rec_order");
        order.setTransac_status("unsettled");
        KdsShopConfig config = new KdsShopConfig();
        config.setSync_legacy_rece(0);
        config.setAuto_off_order_on_kds_done(0);
        when(configService.getOrDefault(1)).thenReturn(config);
        when(orderService.getById(100)).thenReturn(order);

        service.afterOrderKdsStatus(1, 100, KdsOrderStatus.ALL_DONE);

        assertEquals("rec_order", order.getOrder_receiving());
        verify(orderService, never()).updateById(order);
    }

    @Test
    void allDoneClearsTableWhenAutoOffIsEnabled() {
        KdsLegacySyncService service = new KdsLegacySyncService();
        KdsConfigService configService = mock(KdsConfigService.class);
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(service, "configService", configService);
        ReflectionTestUtils.setField(service, "orderDetailService", mock(IOrderDetailService.class));
        ReflectionTestUtils.setField(service, "orderService", orderService);

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("NO101");
        order.setOrder_receiving("rec_order");
        order.setTransac_status("unsettled");
        KdsShopConfig config = new KdsShopConfig();
        config.setSync_legacy_rece(0);
        config.setAuto_off_order_on_kds_done(1);
        when(configService.getOrDefault(1)).thenReturn(config);
        when(orderService.getById(101)).thenReturn(order);

        service.afterOrderKdsStatus(1, 101, KdsOrderStatus.ALL_DONE);

        assertEquals("off_order", order.getOrder_receiving());
        verify(orderService).updateById(order);
    }
}
