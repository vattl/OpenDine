package com.lanf.service.impl;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ZsqSystemSettings;
import com.lanf.entity.Order;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.dto.ZsqCreateOrderResult;
import com.lanf.integration.service.ZsqDeliveryService;
import com.lanf.integration.web.dto.ZsqDispatchOptionsRequest;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.integration.web.dto.ZsqTakeawayDispatchResult;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserAddressService;
import com.lanf.service.TakeoutDispatchAlertService;
import org.junit.jupiter.api.Test;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class TakeoutZsqRedispatchReuseTest {

    @Test
    void redispatchesCancelledDeliveryOnTheExistingOpenOrder() {
        Fixture fixture = fixture();

        ZsqTakeawayDispatchResult dispatchResult = new ZsqTakeawayDispatchResult();
        dispatchResult.setDispatch(Collections.singletonMap("parentOrderNo", "new-delivery-parent"));
        when(fixture.zsqDeliveryService.dispatchOpenOrderWithConfig(
                eq(54232322L), any(ZsqDispatchOptionsRequest.class)))
                .thenReturn(dispatchResult);

        TakeoutDelivery result = fixture.service.dispatchToZsq(13573, true);

        assertEquals(54232322L, result.getZsq_open_order_id());
        assertEquals("841794065912197", result.getZsq_order_id());
        assertEquals("new-delivery-parent", result.getZsq_parent_order_no());
        assertEquals("dispatched", result.getZsq_dispatch_status());
        verify(fixture.zsqDeliveryService).dispatchOpenOrderWithConfig(
                eq(54232322L), any(ZsqDispatchOptionsRequest.class));
        verify(fixture.zsqDeliveryService, never()).createTakeawayAndDispatchWithConfig(any());
    }

    @Test
    void createsANewOpenOrderOnlyWhenTheExistingOneIsConfirmedMissing() {
        Fixture fixture = fixture();
        when(fixture.zsqDeliveryService.dispatchOpenOrderWithConfig(
                eq(54232322L), any(ZsqDispatchOptionsRequest.class)))
                .thenThrow(new ZsqApiException(404, "订单不存在", "trace-missing"));

        ZsqCreateOrderResult createdOrder = new ZsqCreateOrderResult();
        createdOrder.setId(54239999L);
        createdOrder.setOrderId("new-order-id");
        ZsqTakeawayDispatchResult createdDispatch = new ZsqTakeawayDispatchResult();
        createdDispatch.setOrder(createdOrder);
        createdDispatch.setDispatch(Collections.singletonMap("parentOrderNo", "new-delivery-parent"));
        when(fixture.zsqDeliveryService.createTakeawayAndDispatchWithConfig(any()))
                .thenReturn(createdDispatch);
        when(fixture.zsqDeliveryService.getRiderTrackingWithConfig(54239999L))
                .thenReturn(waitingTracking());

        TakeoutDelivery result = fixture.service.dispatchToZsq(13573, true);

        assertEquals(54239999L, result.getZsq_open_order_id());
        assertEquals("new-order-id", result.getZsq_order_id());
        verify(fixture.zsqDeliveryService).dispatchOpenOrderWithConfig(
                eq(54232322L), any(ZsqDispatchOptionsRequest.class));
        verify(fixture.zsqDeliveryService).createTakeawayAndDispatchWithConfig(any());
    }

    @Test
    void rejectsRedispatchWhileTheCurrentDeliveryIsStillActive() {
        Fixture fixture = fixture();
        fixture.delivery.setDispatch_status("delivering");
        fixture.delivery.setZsq_dispatch_status("dispatched");

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> fixture.service.dispatchToZsq(13573, true));

        assertEquals("当前配送仍在进行中，不能重新叫骑手", error.getMessage());
        verify(fixture.zsqDeliveryService, never()).dispatchOpenOrderWithConfig(
                anyLong(), any(ZsqDispatchOptionsRequest.class));
        verify(fixture.zsqDeliveryService, never()).createTakeawayAndDispatchWithConfig(any());
    }

    private static Fixture fixture() {
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IOrderService orderService = mock(IOrderService.class);
        IShopTakeoutConfigService configService = mock(IShopTakeoutConfigService.class);
        IShopService shopService = mock(IShopService.class);
        IUserAddressService addressService = mock(IUserAddressService.class);
        ZsqDeliveryService zsqDeliveryService = mock(ZsqDeliveryService.class);

        Order order = new Order();
        order.setId(13573);
        order.setShop_id(1);
        order.setDineInOrTakeOut("外卖");
        order.setSett_amount(50D);
        when(orderService.getById(13573)).thenReturn(order);

        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(13573);
        delivery.setShop_id(1);
        delivery.setDispatch_status("cancelled");
        delivery.setZsq_dispatch_status("cancelled");
        delivery.setZsq_open_order_id(54232322L);
        delivery.setZsq_order_id("841794065912197");
        delivery.setZsq_parent_order_no("old-delivery-parent");
        delivery.setReceiver_name("测试用户");
        delivery.setReceiver_phone("13800138000");
        delivery.setAddress_full("鹤山市沙坪街道前进路18号·鹤山市人民政府");
        when(deliveryService.getByOrderId(13573)).thenReturn(delivery);
        ShopTakeoutConfig config = new ShopTakeoutConfig();
        config.setZsq_from_address_id(1001L);
        when(configService.resolveForShop(1)).thenReturn(config);
        when(zsqDeliveryService.getRiderTrackingWithConfig(54232322L))
                .thenReturn(waitingTracking());

        TakeoutZsqIntegrationServiceImpl service = new TakeoutZsqIntegrationServiceImpl(
                deliveryService, orderService, configService, shopService, addressService,
                zsqDeliveryService, new ObjectMapper(), mock(TakeoutDispatchAlertService.class),
                mock(ZsqSystemSettings.class));
        return new Fixture(service, zsqDeliveryService, delivery);
    }

    private static ZsqRiderTrackingResponse waitingTracking() {
        ZsqRiderTrackingResponse tracking = new ZsqRiderTrackingResponse();
        tracking.setPhase("WAITING_RIDER");
        tracking.setDeliverySendStatus(20);
        tracking.setCoordinateType("gcj02");
        return tracking;
    }

    private static final class Fixture {
        private final TakeoutZsqIntegrationServiceImpl service;
        private final ZsqDeliveryService zsqDeliveryService;
        private final TakeoutDelivery delivery;

        private Fixture(TakeoutZsqIntegrationServiceImpl service,
                        ZsqDeliveryService zsqDeliveryService,
                        TakeoutDelivery delivery) {
            this.service = service;
            this.zsqDeliveryService = zsqDeliveryService;
            this.delivery = delivery;
        }
    }
}
