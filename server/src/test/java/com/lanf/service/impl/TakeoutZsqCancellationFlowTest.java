package com.lanf.service.impl;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ZsqSystemSettings;
import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.integration.remote.dto.ZsqCancelResult;
import com.lanf.integration.service.ZsqDeliveryService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserAddressService;
import com.lanf.service.TakeoutDispatchAlertService;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class TakeoutZsqCancellationFlowTest {

    @Test
    void locallyCancelledStatusMustNotSkipRemoteCancellation() {
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IOrderService orderService = mock(IOrderService.class);
        ZsqDeliveryService zsqDeliveryService = mock(ZsqDeliveryService.class);
        Order order = new Order();
        order.setId(13573);
        order.setDineInOrTakeOut("外卖");
        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(13573);
        delivery.setZsq_open_order_id(54237416L);
        delivery.setDispatch_status("cancelled");
        delivery.setZsq_dispatch_status("cancelled");
        ZsqCancelResult remoteResult = new ZsqCancelResult();
        remoteResult.setSuccess(true);
        remoteResult.setMessage("取消成功");
        when(orderService.getById(13573)).thenReturn(order);
        when(deliveryService.getByOrderId(13573)).thenReturn(delivery);
        when(zsqDeliveryService.cancelTakeawayOrderWithConfig(
                54237416L, null, false)).thenReturn(remoteResult);
        TakeoutZsqIntegrationServiceImpl service = new TakeoutZsqIntegrationServiceImpl(
                deliveryService, orderService, mock(IShopTakeoutConfigService.class),
                mock(IShopService.class), mock(IUserAddressService.class), zsqDeliveryService,
                new ObjectMapper(), mock(TakeoutDispatchAlertService.class), mock(ZsqSystemSettings.class));

        ZsqCancelResult result = service.cancelZsqForOrder(13573, "运营取消配送", false);

        assertTrue(result.isSuccess());
        verify(zsqDeliveryService).cancelTakeawayOrderWithConfig(54237416L, null, false);
        verify(deliveryService).updateById(delivery);
    }
}
