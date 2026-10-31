package com.lanf.realtime;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ApiPermissionMapping;
import com.lanf.config.WebSocketConfig;
import com.lanf.controller.NotificationChannelController;
import com.lanf.converter.UserCouponConverter;
import com.lanf.dto.R;
import com.lanf.entity.Coupon;
import com.lanf.entity.Order;
import com.lanf.entity.RealtimeNotification;
import com.lanf.entity.ShopNotificationConfig;
import com.lanf.entity.UserCoupon;
import com.lanf.kds.delivery.CashierKdsLeaseService;
import com.lanf.mapper.ComboMapper;
import com.lanf.mapper.CouponMapper;
import com.lanf.mapper.CouponRedeemCodeMapper;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.RealtimeNotificationMapper;
import com.lanf.mapper.ShopNotificationConfigMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.notify.service.OrderTimeoutWatchdogScheduler;
import com.lanf.notify.service.ShopNotificationConfigService;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.notify.service.WechatCouponSubscribePushService;
import com.lanf.security.JwtTokenService;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import com.lanf.service.IShopService;
import com.lanf.service.impl.ICouponServiceImpl;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistration;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

import java.math.BigDecimal;
import java.net.URI;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class UnifiedNotificationChannelTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void unifiedNotificationPermissionsAndWebSocketEndpointShouldBeRegistered() {
        String getConfigPerm = ApiPermissionMapping.getRequiredPermission("/admin/shop/notification-config");
        assertNotNull(getConfigPerm, "EXPECTED_UNIFIED_NOTIFICATION_CHANNEL_READY");
        assertTrue(getConfigPerm.contains("shop:manage"));
        assertTrue(getConfigPerm.contains("order:config"));

        String syncPerm = ApiPermissionMapping.getRequiredPermission("/cashier/notifications/sync");
        assertNotNull(syncPerm);
        assertTrue(syncPerm.contains("cashier:operate"));

        String ackPerm = ApiPermissionMapping.getRequiredPermission("/cashier/notifications/ack");
        assertNotNull(ackPerm);
        assertTrue(ackPerm.contains("cashier:operate"));

        assertNotNull(ApiPermissionMapping.getRequiredPermission("/api/v1/notifications/sync"));
        assertNotNull(ApiPermissionMapping.getRequiredPermission("/api/v1/notifications/ack"));

        // Verify WebSocketConfig registers /ws/v1/notify without breaking /ws/menu, /ws/kds, /ws/cashier-events
        WebSocketConfig wsConfig = new WebSocketConfig();
        DishMenuWebSocketHandler menuHandler = mock(DishMenuWebSocketHandler.class);
        KdsWebSocketHandler kdsHandler = mock(KdsWebSocketHandler.class);
        CashierEventWebSocketHandler cashierHandler = mock(CashierEventWebSocketHandler.class);
        UnifiedNotificationWebSocketHandler unifiedHandler = mock(UnifiedNotificationWebSocketHandler.class);

        ReflectionTestUtils.setField(wsConfig, "dishMenuWebSocketHandler", menuHandler);
        ReflectionTestUtils.setField(wsConfig, "kdsWebSocketHandler", kdsHandler);
        ReflectionTestUtils.setField(wsConfig, "cashierEventWebSocketHandler", cashierHandler);
        ReflectionTestUtils.setField(wsConfig, "unifiedNotificationWebSocketHandler", unifiedHandler);

        WebSocketHandlerRegistry registry = mock(WebSocketHandlerRegistry.class);
        WebSocketHandlerRegistration registration = mock(WebSocketHandlerRegistration.class);
        when(registry.addHandler(any(WebSocketHandler.class), anyString())).thenReturn(registration);
        when(registry.addHandler(any(WebSocketHandler.class), anyString(), anyString())).thenReturn(registration);
        when(registration.setAllowedOrigins(anyString())).thenReturn(registration);
        when(registration.setAllowedOrigins(any(String[].class))).thenReturn(registration);

        wsConfig.registerWebSocketHandlers(registry);

        verify(registry).addHandler(menuHandler, "/ws/menu");
        verify(registry).addHandler(kdsHandler, "/ws/kds", "/ws/kds/v2");
        verify(registry).addHandler(cashierHandler, "/ws/cashier-events");
        verify(registry).addHandler(unifiedHandler, "/ws/v1/notify");
    }

    @Test
    void dynamicShopNotificationConfigShouldDefaultValidateAndPersist() {
        ShopNotificationConfigMapper configMapper = mock(ShopNotificationConfigMapper.class);
        Map<Integer, ShopNotificationConfig> dbStore = new ConcurrentHashMap<>();
        when(configMapper.selectById(any())).thenAnswer(inv -> dbStore.get((Integer) inv.getArgument(0)));
        when(configMapper.insert(any(ShopNotificationConfig.class))).thenAnswer(inv -> {
            ShopNotificationConfig c = inv.getArgument(0);
            dbStore.put(c.getShop_id(), c);
            return 1;
        });
        when(configMapper.updateById(any(ShopNotificationConfig.class))).thenAnswer(inv -> {
            ShopNotificationConfig c = inv.getArgument(0);
            dbStore.put(c.getShop_id(), c);
            return 1;
        });

        ShopNotificationConfigService configService = new ShopNotificationConfigService(configMapper);
        UnifiedNotificationService notificationService = mock(UnifiedNotificationService.class);
        NotificationChannelController controller = new NotificationChannelController(notificationService, configService);

        MockHttpServletRequest req = new MockHttpServletRequest();
        req.addHeader("X-Shop-Id", "12");

        // 1. Default config for shop 12: enabled=true, minutes=15, repeat=60
        com.lanf.entity.R getDefaultResp = controller.getShopNotificationConfig(12, null, req);
        assertEquals(0, getDefaultResp.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> defaultData = (Map<String, Object>) getDefaultResp.get("data");
        assertEquals(12, defaultData.get("shop_id"));
        assertEquals(Boolean.TRUE, defaultData.get("prep_timeout_enabled"));
        assertEquals(15, defaultData.get("prep_timeout_minutes"));
        assertEquals(60, defaultData.get("timeout_repeat_interval_seconds"));

        // 2. Reject invalid threshold (< 5 minutes or > 120 minutes)
        Map<String, Object> invalidBody = new HashMap<>();
        invalidBody.put("shop_id", 12);
        invalidBody.put("prep_timeout_enabled", true);
        invalidBody.put("prep_timeout_minutes", 3);
        com.lanf.entity.R badResp = controller.updateShopNotificationConfig(invalidBody, req);
        assertEquals(400, badResp.get("code"));

        invalidBody.put("prep_timeout_minutes", 180);
        com.lanf.entity.R badRespHigh = controller.updateShopNotificationConfig(invalidBody, req);
        assertEquals(400, badRespHigh.get("code"));

        // 3. Valid update (25 minutes, repeat 45 seconds)
        Map<String, Object> validBody = new HashMap<>();
        validBody.put("shop_id", 12);
        validBody.put("prep_timeout_enabled", true);
        validBody.put("prep_timeout_minutes", 25);
        validBody.put("timeout_repeat_interval_seconds", 45);
        com.lanf.entity.R okResp = controller.updateShopNotificationConfig(validBody, req);
        assertEquals(0, okResp.get("code"));

        ShopNotificationConfig reloaded = configService.getOrDefaultConfig(12);
        assertEquals(1, reloaded.getPrep_timeout_enabled());
        assertEquals(25, reloaded.getPrep_timeout_minutes());
        assertEquals(45, reloaded.getTimeout_repeat_interval_seconds());
    }

    @Test
    void watchdogShouldTriggerDynamicOrderPrepTimeoutAndDeduplicate() throws Exception {
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);

        List<RealtimeNotification> persisted = new ArrayList<>();
        AtomicLong seqGen = new AtomicLong(500L);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        when(notificationMapper.insert(any(RealtimeNotification.class))).thenAnswer(inv -> {
            RealtimeNotification r = inv.getArgument(0);
            r.setSeq_id(seqGen.incrementAndGet());
            persisted.add(r);
            return 1;
        });
        when(notificationMapper.selectCount(any())).thenAnswer(inv -> persisted.isEmpty() ? 0 : 1);

        UnifiedNotificationService notificationService = new UnifiedNotificationService(
                notificationMapper, registry, null);

        ShopNotificationConfigMapper configMapper = mock(ShopNotificationConfigMapper.class);
        ShopNotificationConfig shop1Cfg = new ShopNotificationConfig();
        shop1Cfg.setShop_id(1);
        shop1Cfg.setPrep_timeout_enabled(1);
        shop1Cfg.setPrep_timeout_minutes(10); // Dynamic 10-minute threshold for Shop 1
        shop1Cfg.setTimeout_repeat_interval_seconds(45);

        ShopNotificationConfig shop2Cfg = new ShopNotificationConfig();
        shop2Cfg.setShop_id(2);
        shop2Cfg.setPrep_timeout_enabled(0); // Disabled for Shop 2
        shop2Cfg.setPrep_timeout_minutes(10);

        when(configMapper.selectById(1)).thenReturn(shop1Cfg);
        when(configMapper.selectById(2)).thenReturn(shop2Cfg);
        ShopNotificationConfigService configService = new ShopNotificationConfigService(configMapper);

        long nowMs = 1_730_000_000_000L;

        // Order A: Shop 1, paid 12 minutes ago (>= 10 min threshold) -> SHOULD trigger P0 timeout
        Order orderTimedOut = new Order();
        orderTimedOut.setId(101);
        orderTimedOut.setOrder_no("ORD_TIMEOUT_101");
        orderTimedOut.setShop_id(1);
        orderTimedOut.setTable_number("A08");
        orderTimedOut.setDineInOrTakeOut("堂食");
        orderTimedOut.setTransac_status("success");
        orderTimedOut.setPay_time(new Date(nowMs - 12 * 60_000L));

        // Order B: Shop 1, paid 6 minutes ago (< 10 min threshold) -> SHOULD NOT trigger
        Order orderFresh = new Order();
        orderFresh.setId(102);
        orderFresh.setOrder_no("ORD_FRESH_102");
        orderFresh.setShop_id(1);
        orderFresh.setTransac_status("success");
        orderFresh.setPay_time(new Date(nowMs - 6 * 60_000L));

        // Order C: Shop 2 (disabled), paid 20 minutes ago -> SHOULD NOT trigger
        Order orderDisabledShop = new Order();
        orderDisabledShop.setId(103);
        orderDisabledShop.setOrder_no("ORD_SHOP2_103");
        orderDisabledShop.setShop_id(2);
        orderDisabledShop.setTransac_status("success");
        orderDisabledShop.setPay_time(new Date(nowMs - 20 * 60_000L));

        OrderMapper orderMapper = mock(OrderMapper.class);
        when(orderMapper.selectList(any())).thenReturn(Arrays.asList(orderTimedOut, orderFresh, orderDisabledShop));

        // Register a Cashier WebSocket session for Shop 1
        List<String> sentFrames = new ArrayList<>();
        WebSocketSession cashierSession = createRecordingSession("cashier-s1", sentFrames);
        registry.register(cashierSession, "CASHIER", 1, null, null, 1, "POS-01");

        OrderTimeoutWatchdogScheduler watchdog = new OrderTimeoutWatchdogScheduler(
                orderMapper, configService, notificationService);

        List<UnifiedMessageEnvelope> firstRun = watchdog.scanAndNotifyTimedOutOrders(nowMs);
        assertEquals(1, firstRun.size());
        UnifiedMessageEnvelope alert = firstRun.get(0);
        assertEquals("ntf_timeout_ORD_TIMEOUT_101_stage1", alert.getMessage_id());
        assertEquals("ORDER_PREP_TIMEOUT", alert.getEvent_type());
        assertEquals("P0", alert.getPriority());
        assertEquals(Boolean.TRUE, alert.getRequire_ack());
        assertEquals(45_000L, alert.getDisplay_strategy().getRepeat_interval_ms());
        assertEquals(10, alert.getPayload().get("timeout_threshold_minutes"));
        assertEquals(12, alert.getPayload().get("elapsed_minutes"));
        assertEquals(1, sentFrames.size());

        // Second scan must deduplicate and not emit duplicate alert
        List<UnifiedMessageEnvelope> secondRun = watchdog.scanAndNotifyTimedOutOrders(nowMs + 30_000L);
        assertTrue(secondRun.isEmpty());
        assertEquals(1, sentFrames.size());
    }

    @Test
    void couponGrantShouldPushRealtimeWhenOnlineAndFallbackToSubscribeMessageWhenOffline() throws Exception {
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        WechatCouponSubscribePushService subscribePushService = mock(WechatCouponSubscribePushService.class);
        when(subscribePushService.sendCouponGrantedSubscribeMessage(anyString(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(true);

        UnifiedNotificationService notificationService = new UnifiedNotificationService(
                notificationMapper, registry, subscribePushService);

        CouponMapper couponMapper = mock(CouponMapper.class);
        CouponRedeemCodeMapper redeemMapper = mock(CouponRedeemCodeMapper.class);
        UserCouponMapper userCouponMapper = mock(UserCouponMapper.class);
        OrderMapper orderMapper = mock(OrderMapper.class);
        ComboMapper comboMapper = mock(ComboMapper.class);
        UserCouponConverter converter = mock(UserCouponConverter.class);
        IDishService dishService = mock(IDishService.class);
        IShopService shopService = mock(IShopService.class);

        Coupon template = new Coupon();
        template.setId(88L);
        template.setCoupon_name("新人满30减10元券");
        template.setCoupon_type("full_reduction");
        template.setDiscount_value(new BigDecimal("10"));
        template.setMin_amount(new BigDecimal("30"));
        template.setStock(100);
        template.setStatus(1);
        template.setValidity_time(72);
        when(couponMapper.selectValidCouponById(88L)).thenReturn(template);

        AtomicLong ucIdGen = new AtomicLong(9000L);
        when(userCouponMapper.insert(any(UserCoupon.class))).thenAnswer(inv -> {
            UserCoupon uc = inv.getArgument(0);
            uc.setId(ucIdGen.incrementAndGet());
            return 1;
        });

        ICouponServiceImpl couponService = new ICouponServiceImpl(
                couponMapper, redeemMapper, userCouponMapper, orderMapper,
                comboMapper, converter, dishService, shopService, objectMapper);
        couponService.setUnifiedNotificationService(notificationService);

        // Case 1: Online user "openid_online_user" -> receives WebSocket COUPON_GRANTED, NO offline subscribe push
        List<String> userWsMessages = new ArrayList<>();
        WebSocketSession userSession = createRecordingSession("mp-u1", userWsMessages);
        registry.register(userSession, "MINI_PROGRAM", 1, "openid_online_user", 501, null, null);

        R<Void> resOnline = couponService.receiveCoupon("openid_online_user", 88L);
        assertEquals(0, resOnline.getCode());
        assertEquals(1, userWsMessages.size());

        UnifiedMessageEnvelope wsCouponEnv = objectMapper.readValue(userWsMessages.get(0), UnifiedMessageEnvelope.class);
        assertEquals("COUPON_GRANTED", wsCouponEnv.getEvent_type());
        assertEquals("P1", wsCouponEnv.getPriority());
        assertEquals("COUPON_GRANTED", wsCouponEnv.getDisplay_strategy().getAggregation_key());
        assertEquals(800L, wsCouponEnv.getDisplay_strategy().getAggregation_window_ms());
        assertEquals("新人满30减10元券", wsCouponEnv.getPayload().get("coupon_name"));
        verify(subscribePushService, never()).sendCouponGrantedSubscribeMessage(
                eq("openid_online_user"), anyString(), anyString(), anyString(), anyString());

        // Case 2: Offline user "openid_offline_user" -> triggers offline WeChat Subscribe Message fallback
        R<Void> resOffline = couponService.receiveCoupon("openid_offline_user", 88L);
        assertEquals(0, resOffline.getCode());
        verify(subscribePushService, times(1)).sendCouponGrantedSubscribeMessage(
                eq("openid_offline_user"), eq("新人满30减10元券"), contains("满30减10元"), anyString(), anyString());
    }

    @Test
    void websocketHandlerSyncAndMultiDeviceAckShouldDismissAcrossShopTerminals() throws Exception {
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);

        Map<Long, RealtimeNotification> dbNotifications = new ConcurrentHashMap<>();
        AtomicLong seqCounter = new AtomicLong(100L);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        when(notificationMapper.insert(any(RealtimeNotification.class))).thenAnswer(inv -> {
            RealtimeNotification n = inv.getArgument(0);
            long seq = seqCounter.incrementAndGet();
            n.setSeq_id(seq);
            dbNotifications.put(seq, n);
            return 1;
        });
        when(notificationMapper.selectShopMaxSeqId(anyInt())).thenAnswer(inv -> seqCounter.get());
        when(notificationMapper.selectList(any())).thenAnswer(inv -> {
            List<RealtimeNotification> list = new ArrayList<>(dbNotifications.values());
            list.sort((a, b) -> Long.compare(a.getSeq_id(), b.getSeq_id()));
            return list;
        });
        when(notificationMapper.update(isNull(), any())).thenReturn(1);

        UnifiedNotificationService notificationService = new UnifiedNotificationService(
                notificationMapper, registry, null);

        JwtTokenService jwtTokenService = mock(JwtTokenService.class);
        Claims adminClaims = Jwts.claims().setSubject("admin").setId("7");
        when(jwtTokenService.parseToken("valid-jwt-token")).thenReturn(adminClaims);
        when(jwtTokenService.parseToken("bad-token")).thenThrow(new RuntimeException("invalid jwt"));

        CashierKdsLeaseService leaseService = mock(CashierKdsLeaseService.class);
        UnifiedNotificationWebSocketHandler handler = new UnifiedNotificationWebSocketHandler(
                registry, notificationService, jwtTokenService, leaseService);

        // 1. Unauthorized cashier connection must be closed with POLICY_VIOLATION
        List<String> unauthorizedMsgs = new ArrayList<>();
        WebSocketSession badSession = createRecordingSession(
                "bad-s", new URI("ws://localhost/ws/v1/notify?client_type=CASHIER&shop_id=1&token=bad-token"), unauthorizedMsgs);
        handler.afterConnectionEstablished(badSession);
        verify(badSession).close(argThat(status -> status.getCode() == CloseStatus.POLICY_VIOLATION.getCode()));

        // 2. Two valid Cashier POS terminals connect for Shop 1
        List<String> pos1Msgs = new ArrayList<>();
        WebSocketSession pos1 = createRecordingSession(
                "pos-1", new URI("ws://localhost/ws/v1/notify?client_type=CASHIER&shop_id=1&token=valid-jwt-token&device_id=POS-A"), pos1Msgs);
        handler.afterConnectionEstablished(pos1);
        assertEquals(1, pos1Msgs.size());
        assertTrue(pos1Msgs.get(0).contains("\"frame_type\":\"CONNECTED\""));

        List<String> pos2Msgs = new ArrayList<>();
        WebSocketSession pos2 = createRecordingSession(
                "pos-2", new URI("ws://localhost/ws/v1/notify?client_type=CASHIER&shop_id=1&token=valid-jwt-token&device_id=POS-B"), pos2Msgs);
        handler.afterConnectionEstablished(pos2);

        // 3. Publish NEW_ORDER_PAID -> both POS-A and POS-B receive it
        Order paidOrder = new Order();
        paidOrder.setId(555);
        paidOrder.setOrder_no("ORD20261031001");
        paidOrder.setShop_id(1);
        paidOrder.setTable_number("B12");
        paidOrder.setDineInOrTakeOut("堂食");
        paidOrder.setPayment_method("微信支付");
        UnifiedMessageEnvelope orderEnv = notificationService.publishNewOrderPaid(paidOrder, 128.50);
        assertNotNull(orderEnv);
        assertEquals("NEW_ORDER_PAID", orderEnv.getEvent_type());
        assertEquals(2, pos1Msgs.size());
        assertEquals(2, pos2Msgs.size());

        // 4. Heartbeat PING -> PONG with latest server_head_seq_id
        handler.handleTextMessage(pos1, new TextMessage("{\"frame_type\":\"PING\"}"));
        assertEquals(3, pos1Msgs.size());
        assertTrue(pos1Msgs.get(2).contains("\"frame_type\":\"PONG\""));

        // 5. Incremental Sync via REST controller
        ShopNotificationConfigService configService = new ShopNotificationConfigService(mock(ShopNotificationConfigMapper.class));
        NotificationChannelController controller = new NotificationChannelController(notificationService, configService);
        MockHttpServletRequest httpReq = new MockHttpServletRequest();
        httpReq.addHeader("X-Shop-Id", "1");
        com.lanf.entity.R syncResp = controller.syncNotifications(100L, null, 50, 1, null, "CASHIER", null, null, httpReq);
        assertEquals(0, syncResp.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> syncData = (Map<String, Object>) syncResp.get("data");
        @SuppressWarnings("unchecked")
        List<UnifiedMessageEnvelope> syncedItems = (List<UnifiedMessageEnvelope>) syncData.get("items");
        assertEquals(1, syncedItems.size());
        assertEquals("ntf_order_paid_ORD20261031001", syncedItems.get(0).getMessage_id());

        // 6. POS-A acknowledges the alert via WebSocket ACK frame -> POS-B receives ALERT_DISMISSED
        handler.handleTextMessage(pos1, new TextMessage(
                "{\"frame_type\":\"ACK\",\"seq_id\":101,\"message_ids\":[\"ntf_order_paid_ORD20261031001\"]}"));
        boolean pos2ReceivedDismiss = pos2Msgs.stream().anyMatch(m -> m.contains("\"event_type\":\"ALERT_DISMISSED\""));
        assertTrue(pos2ReceivedDismiss, "Sibling POS terminal must receive ALERT_DISMISSED broadcast");

        // 7. Dual-publish bridge verification for CashierEventWebSocketHub and DishMenuPushService
        CashierEventWebSocketHub cashierHub = new CashierEventWebSocketHub(dispatcher);
        cashierHub.setUnifiedNotificationService(notificationService);
        int beforeBridgeCount = pos1Msgs.size();
        cashierHub.broadcastTableOrderChanged(1, "B12", "ORD20261031001", 4);
        assertTrue(pos1Msgs.size() > beforeBridgeCount);
        assertTrue(pos1Msgs.get(pos1Msgs.size() - 1).contains("\"event_type\":\"TABLE_ORDER_CHANGED\""));

        DishMenuPushService dishPushService = new DishMenuPushService();
        ReflectionTestUtils.setField(dishPushService, "eventPublisher", mock(ApplicationEventPublisher.class));
        ReflectionTestUtils.setField(dishPushService, "webSocketHub", mock(DishMenuWebSocketHub.class));
        dishPushService.setUnifiedNotificationService(notificationService);
        int beforeMenuCount = pos1Msgs.size();
        dishPushService.notifyCatalogChanged("updateOnSale", 99, "招牌脆皮鸡", false);
        assertTrue(pos1Msgs.size() > beforeMenuCount);
        assertTrue(pos1Msgs.get(pos1Msgs.size() - 1).contains("\"event_type\":\"DISH_CATALOG_CHANGED\""));
    }

    private static WebSocketOutboundDispatcher createSynchronousDispatcher() {
        WebSocketOutboundDispatcher dispatcher = mock(WebSocketOutboundDispatcher.class);
        when(dispatcher.dispatch(any(WebSocketSession.class), any(TextMessage.class))).thenAnswer(inv -> {
            WebSocketSession s = inv.getArgument(0);
            TextMessage msg = inv.getArgument(1);
            if (s != null && s.isOpen()) {
                s.sendMessage(msg);
                return true;
            }
            return false;
        });
        return dispatcher;
    }

    private static WebSocketSession createRecordingSession(String id, List<String> sink) throws Exception {
        return createRecordingSession(id, new URI("ws://localhost/ws/v1/notify"), sink);
    }

    private static WebSocketSession createRecordingSession(String id, URI uri, List<String> sink) throws Exception {
        WebSocketSession session = mock(WebSocketSession.class);
        Map<String, Object> attrs = new ConcurrentHashMap<>();
        HttpHeaders headers = new HttpHeaders();
        when(session.getId()).thenReturn(id);
        when(session.getUri()).thenReturn(uri);
        when(session.getAttributes()).thenReturn(attrs);
        when(session.getHandshakeHeaders()).thenReturn(headers);
        when(session.isOpen()).thenReturn(true);
        doAnswer(inv -> {
            TextMessage msg = inv.getArgument(0);
            sink.add(msg.getPayload());
            return null;
        }).when(session).sendMessage(any(TextMessage.class));
        return session;
    }
}
