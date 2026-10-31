package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ZsqSystemSettings;
import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.integration.service.ZsqDeliveryService;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.event.KdsEventListener;
import com.lanf.kds.event.KdsOrderStatusChangedEvent;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.ITakeoutZsqIntegrationService;
import com.lanf.service.IUserAddressService;
import com.lanf.service.TakeoutDispatchAlertService;
import com.lanf.service.impl.TakeoutZsqIntegrationServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * KDS 划菜整单完成自动叫骑手单元测试：
 * 1. 堂食/自提订单整单完成跳过叫骑手
 * 2. 外卖订单整单完成自动触发叫骑手
 * 3. 部分制作完成不触发叫骑手
 * 4. 幂等防重：已派单(dispatched/delivering/completed)或正在派单(pending)跳过
 * 5. 第三方接口异常安全降级，不阻断主流程
 * 6. KdsEventListener 事件广播集成联动
 */
public class KdsTakeoutAutoDispatchTest {

    private TakeoutZsqIntegrationServiceImpl takeoutZsqIntegrationService;
    private IOrderService orderService;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private IShopTakeoutConfigService shopTakeoutConfigService;
    private IShopService shopService;
    private IUserAddressService userAddressService;
    private ZsqDeliveryService zsqDeliveryService;
    private ObjectMapper objectMapper;
    private TakeoutDispatchAlertService takeoutDispatchAlertService;
    private ZsqSystemSettings zsqSystemSettings;

    private KdsPushService kdsPushService;
    private KdsEventListener kdsEventListener;

    @BeforeEach
    void setUp() {
        orderService = mock(IOrderService.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        shopTakeoutConfigService = mock(IShopTakeoutConfigService.class);
        shopService = mock(IShopService.class);
        userAddressService = mock(IUserAddressService.class);
        zsqDeliveryService = mock(ZsqDeliveryService.class);
        objectMapper = mock(ObjectMapper.class);
        takeoutDispatchAlertService = mock(TakeoutDispatchAlertService.class);
        zsqSystemSettings = mock(ZsqSystemSettings.class);

        takeoutZsqIntegrationService = spy(new TakeoutZsqIntegrationServiceImpl(
                takeoutDeliveryService,
                orderService,
                shopTakeoutConfigService,
                shopService,
                userAddressService,
                zsqDeliveryService,
                objectMapper,
                takeoutDispatchAlertService,
                zsqSystemSettings
        ));

        kdsPushService = mock(KdsPushService.class);
        kdsEventListener = new KdsEventListener();
        ReflectionTestUtils.setField(kdsEventListener, "pushService", kdsPushService);
        ReflectionTestUtils.setField(kdsEventListener, "takeoutZsqIntegrationService", takeoutZsqIntegrationService);
    }

    @Test
    @DisplayName("非外卖订单（如堂食、打包自提）整单完成时跳过叫骑手")
    void testNonTakeoutOrderSkipsDispatch() {
        int orderId = 1001;
        Order order = new Order();
        order.setId(orderId);
        order.setDineInOrTakeOut("堂食");
        when(orderService.getById(orderId)).thenReturn(order);

        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId);

        verify(takeoutDeliveryService, never()).getByOrderId(anyInt());
        verify(takeoutZsqIntegrationService, never()).dispatchToZsq(anyInt(), anyBoolean());

        // 打包自提
        order.setDineInOrTakeOut("打包");
        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId);
        verify(takeoutZsqIntegrationService, never()).dispatchToZsq(anyInt(), anyBoolean());
    }

    @Test
    @DisplayName("外卖订单整单完成时首次自动触发叫骑手")
    void testTakeoutOrderTriggersDispatchOnKdsCompleted() {
        int orderId = 1002;
        Order order = new Order();
        order.setId(orderId);
        order.setOrder_no("WM202610290001");
        order.setShop_id(5);
        order.setDineInOrTakeOut("外卖");
        when(orderService.getById(orderId)).thenReturn(order);

        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(orderId);
        delivery.setDispatch_status("none");
        delivery.setZsq_dispatch_status("none");
        when(takeoutDeliveryService.getByOrderId(orderId)).thenReturn(delivery);

        doReturn(delivery).when(takeoutZsqIntegrationService).dispatchToZsq(eq(orderId), eq(false));

        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId);

        verify(takeoutZsqIntegrationService, times(1)).dispatchToZsq(eq(orderId), eq(false));
    }

    @Test
    @DisplayName("幂等防重：外卖订单若已派送或派送中则自动跳过，绝无重复呼叫")
    void testIdempotentSkipWhenAlreadyDispatchedOrPending() {
        int orderId = 1003;
        Order order = new Order();
        order.setId(orderId);
        order.setDineInOrTakeOut("外卖");
        when(orderService.getById(orderId)).thenReturn(order);

        // Case 1: zsq_dispatch_status = dispatched
        TakeoutDelivery delivery1 = new TakeoutDelivery();
        delivery1.setZsq_dispatch_status("dispatched");
        when(takeoutDeliveryService.getByOrderId(orderId)).thenReturn(delivery1);
        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId);
        verify(takeoutZsqIntegrationService, never()).dispatchToZsq(anyInt(), anyBoolean());

        // Case 2: zsq_dispatch_status = pending
        TakeoutDelivery delivery2 = new TakeoutDelivery();
        delivery2.setZsq_dispatch_status("pending");
        when(takeoutDeliveryService.getByOrderId(orderId)).thenReturn(delivery2);
        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId);
        verify(takeoutZsqIntegrationService, never()).dispatchToZsq(anyInt(), anyBoolean());

        // Case 3: dispatch_status = delivering
        TakeoutDelivery delivery3 = new TakeoutDelivery();
        delivery3.setDispatch_status("delivering");
        when(takeoutDeliveryService.getByOrderId(orderId)).thenReturn(delivery3);
        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId);
        verify(takeoutZsqIntegrationService, never()).dispatchToZsq(anyInt(), anyBoolean());
    }

    @Test
    @DisplayName("第三方接口异常时安全吞吐并记录日志，不阻断主流程")
    void testThirdPartyExceptionGracefulDegradation() {
        int orderId = 1004;
        Order order = new Order();
        order.setId(orderId);
        order.setShop_id(5);
        order.setOrder_no("WM202610290002");
        order.setDineInOrTakeOut("外卖");
        when(orderService.getById(orderId)).thenReturn(order);

        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setOrder_id(orderId);
        delivery.setDispatch_status("none");
        delivery.setZsq_dispatch_status("none");
        when(takeoutDeliveryService.getByOrderId(orderId)).thenReturn(delivery);

        doThrow(new RuntimeException("真省钱网络超时或余额不足"))
                .when(takeoutZsqIntegrationService).dispatchToZsq(eq(orderId), eq(false));

        assertDoesNotThrow(() -> takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId));
    }

    @Test
    @DisplayName("KdsEventListener 在 ALL_DONE 事件时触发外卖自动叫骑手，非 ALL_DONE 时跳过")
    void testKdsEventListenerIntegration() {
        int shopId = 5;
        int orderId = 1005;

        // 非 ALL_DONE (例如 COOKING)
        KdsOrderStatusChangedEvent eventCooking = new KdsOrderStatusChangedEvent(
                this, shopId, orderId, "ORD001", KdsOrderStatus.WAITING, KdsOrderStatus.COOKING);
        kdsEventListener.onOrderStatusChanged(eventCooking);
        verify(takeoutZsqIntegrationService, never()).tryAutoDispatchOnKdsCompleted(anyInt());

        // ALL_DONE 事件
        KdsOrderStatusChangedEvent eventAllDone = new KdsOrderStatusChangedEvent(
                this, shopId, orderId, "ORD001", KdsOrderStatus.COOKING, KdsOrderStatus.ALL_DONE);
        kdsEventListener.onOrderStatusChanged(eventAllDone);
        verify(takeoutZsqIntegrationService, times(1)).tryAutoDispatchOnKdsCompleted(eq(orderId));
    }
}
