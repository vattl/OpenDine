package com.lanf.service.impl;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ZsqSystemSettings;
import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.integration.service.ZsqDeliveryService;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserAddressService;
import com.lanf.service.TakeoutDispatchAlertService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class TakeoutZsqTrackingPersistenceTest {

    @Test
    void clearsPreviousRiderWhenStartingNewDispatch() {
        Fixture fixture = fixture("112.964200");

        ReflectionTestUtils.invokeMethod(fixture.service, "markDispatchPending", fixture.delivery);

        assertEquals("pending", fixture.delivery.getZsq_dispatch_status());
        assertNull(fixture.delivery.getZsq_phase());
        assertNull(fixture.delivery.getZsq_delivery_send_status());
        assertNull(fixture.delivery.getZsq_rider_name());
        assertNull(fixture.delivery.getZsq_rider_phone());
        assertNull(fixture.delivery.getZsq_rider_lat());
        assertNull(fixture.delivery.getZsq_rider_lng());
        assertNull(fixture.delivery.getZsq_rider_updated_at());
        assertNull(fixture.delivery.getZsq_actual_fee());
        assertNull(fixture.delivery.getZsq_delivery_supplier_name());
        verify(fixture.deliveryService).updateById(fixture.delivery);
    }

    @Test
    void persistsActualFeeAndSupplierNameWhenReturnedInTracking() {
        Fixture fixture = fixture("112.964200");
        ZsqRiderTrackingResponse tracking = new ZsqRiderTrackingResponse();
        tracking.setPhase("TO_USER");
        tracking.setDeliverySendStatus(40);
        tracking.setActualFee(new BigDecimal("6.13"));
        tracking.setDeliverySupplierName("京东特惠");
        when(fixture.zsqDeliveryService.getRiderTrackingWithConfig(54159992L)).thenReturn(tracking);

        fixture.service.getTrackingForOrder(13573);

        assertEquals(new BigDecimal("6.13"), fixture.delivery.getZsq_actual_fee());
        assertEquals("京东特惠", fixture.delivery.getZsq_delivery_supplier_name());
        verify(fixture.deliveryService).updateById(fixture.delivery);
    }

    @Test
    void doesNotWriteDeliveryWhenTrackingValuesAreUnchanged() {
        Fixture fixture = fixture("112.964200");

        fixture.service.getTrackingForOrder(13573);

        verify(fixture.deliveryService, never()).updateById(any(TakeoutDelivery.class));
    }

    @Test
    void writesDeliveryWhenRiderPositionChanges() {
        Fixture fixture = fixture("112.964300");

        fixture.service.getTrackingForOrder(13573);

        verify(fixture.deliveryService).updateById(any(TakeoutDelivery.class));
    }

    @Test
    void recoversStaleLocalCancellationWhenNewRemoteBatchIsPickingUp() {
        Fixture fixture = fixture("112.964300");
        fixture.delivery.setDispatch_status("cancelled");
        fixture.delivery.setZsq_dispatch_status("cancelled");
        fixture.delivery.setZsq_phase("CANCELLED");
        ZsqRiderTrackingResponse tracking = new ZsqRiderTrackingResponse();
        tracking.setPhase("TO_SHOP");
        tracking.setDeliverySendStatus(30);
        when(fixture.zsqDeliveryService.getRiderTrackingWithConfig(54159992L)).thenReturn(tracking);

        fixture.service.getTrackingForOrder(13573);

        assertEquals("delivering", fixture.delivery.getDispatch_status());
        assertEquals("dispatched", fixture.delivery.getZsq_dispatch_status());
        assertEquals("TO_SHOP", fixture.delivery.getZsq_phase());
        assertEquals(30, fixture.delivery.getZsq_delivery_send_status());
    }

    @Test
    void marksDeletedRemoteOrderAsRedispatchableAndReturnsClearMessage() {
        Fixture fixture = fixture("112.964200");
        when(fixture.zsqDeliveryService.getRiderTrackingWithConfig(54159992L))
                .thenThrow(new ZsqApiException(404, "配送订单不存在或已删除", "trace-delete"));

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> fixture.service.getTrackingForOrder(13573));

        assertEquals("真省钱配送订单不存在或已删除，可重新下单配送", error.getMessage());
        assertEquals("dispatch_failed", fixture.delivery.getDispatch_status());
        assertEquals("order_missing", fixture.delivery.getZsq_dispatch_status());
        assertEquals("ORDER_MISSING", fixture.delivery.getZsq_phase());
        assertNull(fixture.delivery.getZsq_open_order_id());

        IllegalStateException repeated = assertThrows(IllegalStateException.class,
                () -> fixture.service.getTrackingForOrder(13573));
        assertEquals("真省钱配送订单不存在或已删除，可重新下单配送", repeated.getMessage());

        verify(fixture.deliveryService).updateById(fixture.delivery);
        verify(fixture.alertService).onRemoteOrderMissing(fixture.delivery, 54159992L);
    }

    @Test
    void doesNotMarkRemoteOrderMissingForTemporaryZsqFailure() {
        Fixture fixture = fixture("112.964200");
        when(fixture.zsqDeliveryService.getRiderTrackingWithConfig(54159992L))
                .thenThrow(new ZsqApiException(500, "真省钱系统繁忙", "trace-busy"));

        assertThrows(ZsqApiException.class,
                () -> fixture.service.getTrackingForOrder(13573));

        assertEquals("dispatched", fixture.delivery.getZsq_dispatch_status());
        assertEquals(54159992L, fixture.delivery.getZsq_open_order_id());
        verify(fixture.deliveryService, never()).updateById(any(TakeoutDelivery.class));
        verify(fixture.alertService, never()).onRemoteOrderMissing(any(TakeoutDelivery.class), any(Long.class));
    }

    private static Fixture fixture(String remoteRiderLng) {
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IOrderService orderService = mock(IOrderService.class);
        IShopTakeoutConfigService configService = mock(IShopTakeoutConfigService.class);
        IShopService shopService = mock(IShopService.class);
        IUserAddressService addressService = mock(IUserAddressService.class);
        ZsqDeliveryService zsqDeliveryService = mock(ZsqDeliveryService.class);
        TakeoutDispatchAlertService alertService = mock(TakeoutDispatchAlertService.class);
        ZsqSystemSettings settings = mock(ZsqSystemSettings.class);

        Order order = new Order();
        order.setId(13573);
        order.setShop_id(1);
        order.setDineInOrTakeOut("外卖");
        when(orderService.getById(13573)).thenReturn(order);

        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(13573);
        delivery.setShop_id(1);
        delivery.setZsq_open_order_id(54159992L);
        delivery.setDispatch_status("delivering");
        delivery.setZsq_dispatch_status("dispatched");
        delivery.setZsq_phase("TO_USER");
        delivery.setZsq_delivery_send_status(40);
        delivery.setZsq_rider_name("骑手");
        delivery.setZsq_rider_phone("13800000000");
        delivery.setZsq_rider_lat(new BigDecimal("22.766000"));
        delivery.setZsq_rider_lng(new BigDecimal("112.964200"));
        when(deliveryService.getByOrderId(13573)).thenReturn(delivery);

        ZsqRiderTrackingResponse tracking = new ZsqRiderTrackingResponse();
        tracking.setPhase("TO_USER");
        tracking.setDeliverySendStatus(40);
        ZsqRiderTrackingResponse.RiderPoint rider = new ZsqRiderTrackingResponse.RiderPoint();
        rider.setName("骑手");
        rider.setPhone("13800000000");
        rider.setLat(22.766000);
        rider.setLng(Double.parseDouble(remoteRiderLng));
        tracking.setRider(rider);
        when(zsqDeliveryService.getRiderTrackingWithConfig(54159992L)).thenReturn(tracking);

        TakeoutZsqIntegrationServiceImpl service = new TakeoutZsqIntegrationServiceImpl(
                deliveryService, orderService, configService, shopService, addressService,
                zsqDeliveryService, new ObjectMapper(), alertService, settings);
        return new Fixture(service, deliveryService, zsqDeliveryService, alertService, delivery);
    }

    private static final class Fixture {
        private final TakeoutZsqIntegrationServiceImpl service;
        private final ITakeoutDeliveryService deliveryService;
        private final ZsqDeliveryService zsqDeliveryService;
        private final TakeoutDispatchAlertService alertService;
        private final TakeoutDelivery delivery;

        private Fixture(TakeoutZsqIntegrationServiceImpl service,
                        ITakeoutDeliveryService deliveryService,
                        ZsqDeliveryService zsqDeliveryService,
                        TakeoutDispatchAlertService alertService,
                        TakeoutDelivery delivery) {
            this.service = service;
            this.deliveryService = deliveryService;
            this.zsqDeliveryService = zsqDeliveryService;
            this.alertService = alertService;
            this.delivery = delivery;
        }
    }
}
