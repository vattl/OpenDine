package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.TakeoutDelivery;
import org.junit.jupiter.api.Test;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class TakeoutDispatchAlertServiceTest {

    @Test
    void publishesOrderMissingAlertAndAuditLog() {
        IOperationLogService operationLogService = mock(IOperationLogService.class);
        DishMenuPushService pushService = mock(DishMenuPushService.class);
        TakeoutDispatchAlertService service = new TakeoutDispatchAlertService(
                operationLogService, pushService, new ObjectMapper());
        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(13573);
        delivery.setOrder_no("ORDER-13573");
        delivery.setShop_id(1);
        delivery.setZsq_phase("ORDER_MISSING");
        delivery.setZsq_last_error("真省钱配送订单不存在或已删除，可重新下单配送");

        service.onRemoteOrderMissing(delivery, 54159992L);

        verify(operationLogService).recordSystem(
                eq(1), eq("takeout"), eq("zsq_order_missing"), eq("ORDER-13573"), anyString());
        verify(pushService).notifyTakeoutDispatchAlert(
                "order_missing", 1, 13573, "ORDER-13573",
                "真省钱配送订单不存在或已删除，可重新下单配送", 54159992L);
    }
}
