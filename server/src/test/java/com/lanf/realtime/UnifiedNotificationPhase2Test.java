package com.lanf.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ApiPermissionMapping;
import com.lanf.controller.NotificationChannelController;
import com.lanf.entity.ActivityPopup;
import com.lanf.entity.Announcement;
import com.lanf.entity.Coupon;
import com.lanf.entity.Order;
import com.lanf.entity.QueueTicket;
import com.lanf.entity.R;
import com.lanf.entity.RealtimeNotification;
import com.lanf.entity.UserCoupon;
import com.lanf.kds.delivery.CashierKdsLeaseService;
import com.lanf.kds.service.KdsCustomerPickupNoticeService;
import com.lanf.kds.service.KdsPushService;
import com.lanf.mapper.CouponMapper;
import com.lanf.mapper.RealtimeNotificationMapper;
import com.lanf.mapper.ShopNotificationConfigMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.notify.service.CouponExpiringWatchdogScheduler;
import com.lanf.notify.service.ShopNotificationConfigService;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.notify.service.WechatCouponSubscribePushService;
import com.lanf.security.JwtTokenService;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IOrderService;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.math.BigDecimal;
import java.net.URI;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class UnifiedNotificationPhase2Test {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void cSideUserTokenAuthAndAntiSpoofingShouldBeEnforcedOnRestAndWebSocket() throws Exception {
        String userSyncPerm = ApiPermissionMapping.getRequiredPermission("/user/notifications/sync");
        assertNotNull(userSyncPerm, "EXPECTED_UNIFIED_NOTIFICATION_PHASE2_READY");
        assertNotNull(ApiPermissionMapping.getRequiredPermission("/user/notifications/ack"));

        UnifiedNotificationService notificationService = mock(UnifiedNotificationService.class);
        when(notificationService.syncNotifications(anyInt(), anyString(), anyString(), anyLong(), any()))
                .thenAnswer(inv -> {
                    Map<String, Object> m = new HashMap<>();
                    m.put("resolved_openid", inv.getArgument(2));
                    m.put("resolved_client_type", inv.getArgument(1));
                    m.put("items", Collections.emptyList());
                    return m;
                });
        when(notificationService.acknowledgeNotifications(any(), anyString(), anyList(), anyString()))
                .thenAnswer(inv -> {
                    Map<String, Object> m = new HashMap<>();
                    m.put("acked_openid", inv.getArgument(1));
                    m.put("acked_count", 1);
                    return m;
                });

        JwtTokenService jwtTokenService = mock(JwtTokenService.class);
        Claims aliceClaims = Jwts.claims().setSubject("user").setId("openid_alice");
        when(jwtTokenService.parseToken("user-jwt-alice")).thenReturn(aliceClaims);
        when(jwtTokenService.parseToken("invalid-user-jwt")).thenThrow(new RuntimeException("expired"));

        ShopNotificationConfigService configService = new ShopNotificationConfigService(mock(ShopNotificationConfigMapper.class));
        NotificationChannelController controller = new NotificationChannelController(
                notificationService, configService, jwtTokenService);

        // 1. Valid X-User-Token auto-binds openid="openid_alice" when openid param is omitted
        MockHttpServletRequest reqAlice = new MockHttpServletRequest("GET", "/user/notifications/sync");
        reqAlice.addHeader("X-User-Token", "user-jwt-alice");
        R okSync = controller.syncNotifications(0L, null, 20, 1, null, null, null, null, reqAlice);
        assertEquals(0, okSync.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> syncData = (Map<String, Object>) okSync.get("data");
        assertEquals("openid_alice", syncData.get("resolved_openid"));
        assertEquals("MINI_PROGRAM", syncData.get("resolved_client_type"));

        // 2. Spoofed openid ("openid_bob") with Alice's X-User-Token must be rejected with 403
        R spoofSync = controller.syncNotifications(0L, null, 20, 1, null, "MINI_PROGRAM", null, "openid_bob", reqAlice);
        assertEquals(403, spoofSync.get("code"));

        Map<String, Object> spoofAckBody = new HashMap<>();
        spoofAckBody.put("openid", "openid_bob");
        spoofAckBody.put("message_ids", Collections.singletonList("ntf_coupon_1"));
        R spoofAck = controller.acknowledgeNotifications(spoofAckBody, reqAlice);
        assertEquals(403, spoofAck.get("code"));

        // 3. Invalid X-User-Token must be rejected with 401
        MockHttpServletRequest reqInvalid = new MockHttpServletRequest("GET", "/api/v1/notifications/sync");
        reqInvalid.addHeader("X-User-Token", "invalid-user-jwt");
        R badTokenSync = controller.syncNotifications(0L, null, 20, 1, null, "MINI_PROGRAM", null, null, reqInvalid);
        assertEquals(401, badTokenSync.get("code"));

        // 4. WebSocket handshake with valid user token auto-binds openid="openid_alice"
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);
        UnifiedNotificationWebSocketHandler wsHandler = new UnifiedNotificationWebSocketHandler(
                registry, notificationService, jwtTokenService, mock(CashierKdsLeaseService.class));

        List<String> aliceWsFrames = new ArrayList<>();
        WebSocketSession aliceSession = createRecordingSession(
                "mp-alice",
                new URI("ws://localhost/ws/v1/notify?client_type=MINI_PROGRAM&shop_id=1&token=user-jwt-alice"),
                aliceWsFrames);
        wsHandler.afterConnectionEstablished(aliceSession);
        assertEquals(1, aliceWsFrames.size());
        assertTrue(aliceWsFrames.get(0).contains("\"openid\":\"openid_alice\""));
        assertTrue(registry.isUserOnline("openid_alice"));

        // 5. WebSocket handshake with spoofed openid mismatching user token must be closed with POLICY_VIOLATION (1008)
        List<String> spoofWsFrames = new ArrayList<>();
        WebSocketSession spoofSession = createRecordingSession(
                "mp-spoof",
                new URI("ws://localhost/ws/v1/notify?client_type=MINI_PROGRAM&shop_id=1&openid=openid_bob&token=user-jwt-alice"),
                spoofWsFrames);
        wsHandler.afterConnectionEstablished(spoofSession);
        verify(spoofSession).close(argThat(status -> status.getCode() == CloseStatus.POLICY_VIOLATION.getCode()));
    }

    @Test
    void expiringCouponWatchdogShouldPushRealtimeAndFallbackToSubscribeWhenOffline() throws Exception {
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);

        List<RealtimeNotification> persisted = new ArrayList<>();
        AtomicLong seqGen = new AtomicLong(800L);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        when(notificationMapper.insert(any(RealtimeNotification.class))).thenAnswer(inv -> {
            RealtimeNotification r = inv.getArgument(0);
            r.setSeq_id(seqGen.incrementAndGet());
            persisted.add(r);
            return 1;
        });
        when(notificationMapper.selectCount(any())).thenAnswer(inv -> persisted.size() >= 2 ? 1 : 0);

        WechatCouponSubscribePushService subscribePush = mock(WechatCouponSubscribePushService.class);
        when(subscribePush.sendCouponExpiringSubscribeMessage(anyString(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(true);

        UnifiedNotificationService notificationService = new UnifiedNotificationService(
                notificationMapper, registry, subscribePush);

        long nowMs = 1_730_000_000_000L;

        // Coupon 1: Online user, expires in 45 minutes (within 120m window)
        UserCoupon ucOnline = new UserCoupon();
        ucOnline.setId(301L);
        ucOnline.setUser_openid("openid_online_exp");
        ucOnline.setCoupon_id(10L);
        ucOnline.setStatus(0);
        ucOnline.setExpire_time(new Date(nowMs + 45 * 60_000L));

        // Coupon 2: Offline user, expires in 30 minutes (within 120m window)
        UserCoupon ucOffline = new UserCoupon();
        ucOffline.setId(302L);
        ucOffline.setUser_openid("openid_offline_exp");
        ucOffline.setCoupon_id(10L);
        ucOffline.setStatus(0);
        ucOffline.setExpire_time(new Date(nowMs + 30 * 60_000L));

        // Coupon 3: Online user, expires in 240 minutes (outside 120m window)
        UserCoupon ucFar = new UserCoupon();
        ucFar.setId(303L);
        ucFar.setUser_openid("openid_online_exp");
        ucFar.setCoupon_id(10L);
        ucFar.setStatus(0);
        ucFar.setExpire_time(new Date(nowMs + 240 * 60_000L));

        UserCouponMapper userCouponMapper = mock(UserCouponMapper.class);
        when(userCouponMapper.selectList(any())).thenReturn(Arrays.asList(ucOnline, ucOffline, ucFar));

        Coupon template = new Coupon();
        template.setId(10L);
        template.setCoupon_name("周末满50减15元券");
        template.setCoupon_type("full_reduction");
        template.setDiscount_value(new BigDecimal("15"));
        template.setMin_amount(new BigDecimal("50"));
        CouponMapper couponMapper = mock(CouponMapper.class);
        when(couponMapper.selectById(10L)).thenReturn(template);

        List<String> onlineUserFrames = new ArrayList<>();
        WebSocketSession onlineSession = createRecordingSession("mp-exp-online", onlineUserFrames);
        registry.register(onlineSession, "MINI_PROGRAM", 1, "openid_online_exp", null, null, null);

        CouponExpiringWatchdogScheduler watchdog = new CouponExpiringWatchdogScheduler(
                userCouponMapper, couponMapper, notificationService);
        watchdog.setExpiringWindowMinutes(120);

        List<UnifiedMessageEnvelope> firstScan = watchdog.scanAndNotifyExpiringCoupons(nowMs);
        assertEquals(2, firstScan.size());
        assertEquals(1, onlineUserFrames.size());

        UnifiedMessageEnvelope onlineEnv = objectMapper.readValue(onlineUserFrames.get(0), UnifiedMessageEnvelope.class);
        assertEquals("ntf_coupon_exp_301", onlineEnv.getMessage_id());
        assertEquals("COUPON_EXPIRING_SOON", onlineEnv.getEvent_type());
        assertEquals("P2", onlineEnv.getPriority());
        assertEquals("BOTTOM_SNACKBAR", onlineEnv.getDisplay_strategy().getUi_type());
        assertEquals("周末满50减15元券", onlineEnv.getPayload().get("coupon_name"));
        assertEquals(45, ((Number) onlineEnv.getPayload().get("remaining_minutes")).intValue());

        // Online user should NOT receive WeChat subscribe fallback; offline user MUST receive it
        verify(subscribePush, never()).sendCouponExpiringSubscribeMessage(
                eq("openid_online_exp"), anyString(), anyString(), anyString(), anyString());
        verify(subscribePush, times(1)).sendCouponExpiringSubscribeMessage(
                eq("openid_offline_exp"), eq("周末满50减15元券"), contains("满50减15元"), anyString(), anyString());

        // Second scan must deduplicate
        List<UnifiedMessageEnvelope> secondScan = watchdog.scanAndNotifyExpiringCoupons(nowMs + 60_000L);
        assertTrue(secondScan.isEmpty());
    }

    @Test
    void customerPickupReadyAndRefundRequestedShouldRouteToTargetRecipients() throws Exception {
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        UnifiedNotificationService notificationService = new UnifiedNotificationService(
                notificationMapper, registry, null);

        List<String> customerFrames = new ArrayList<>();
        WebSocketSession customerSession = createRecordingSession("mp-cust-777", customerFrames);
        registry.register(customerSession, "MINI_PROGRAM", 1, "openid_customer_777", null, null, null);

        List<String> cashierFrames = new ArrayList<>();
        WebSocketSession cashierSession = createRecordingSession("pos-cashier-1", cashierFrames);
        registry.register(cashierSession, "CASHIER", 1, null, null, 1, "POS-01");

        // 1. KDS completes all dishes -> triggers customer-targeted ORDER_READY_FOR_PICKUP (P0)
        Order pickupOrder = new Order();
        pickupOrder.setId(777);
        pickupOrder.setOrder_no("ORD_PICKUP_777");
        pickupOrder.setShop_id(1);
        pickupOrder.setOpenid("openid_customer_777");
        pickupOrder.setTable_number("C05");
        pickupOrder.setDineInOrTakeOut("自提");
        pickupOrder.setNotice(0);

        IOrderService orderService = mock(IOrderService.class);
        when(orderService.getById(777)).thenReturn(pickupOrder);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        DishMenuPushService dishMenuPushService = mock(DishMenuPushService.class);
        KdsPushService kdsPushService = mock(KdsPushService.class);

        KdsCustomerPickupNoticeService pickupNoticeService = new KdsCustomerPickupNoticeService();
        ReflectionTestUtils.setField(pickupNoticeService, "orderService", orderService);
        ReflectionTestUtils.setField(pickupNoticeService, "dishMenuPushService", dishMenuPushService);
        ReflectionTestUtils.setField(pickupNoticeService, "kdsPushService", kdsPushService);
        pickupNoticeService.setUnifiedNotificationService(notificationService);

        boolean triggered = pickupNoticeService.notifyCustomerPickup(1, 777);
        assertTrue(triggered);
        assertEquals(1, customerFrames.size());
        UnifiedMessageEnvelope pickupEnv = objectMapper.readValue(customerFrames.get(0), UnifiedMessageEnvelope.class);
        assertEquals("ORDER_READY_FOR_PICKUP", pickupEnv.getEvent_type());
        assertEquals("P0", pickupEnv.getPriority());
        assertEquals("TOP_BANNER_AND_VIBRATE", pickupEnv.getDisplay_strategy().getUi_type());
        assertEquals("777", pickupEnv.getPayload().get("pickup_code"));

        // 2. Customer initiates refund request -> triggers REFUND_REQUESTED (P0) ONLY to Cashier POS
        UnifiedMessageEnvelope refundEnv = notificationService.publishRefundRequested(
                pickupOrder, 58.0, "菜品点错申请退款");
        assertNotNull(refundEnv);
        assertEquals("REFUND_REQUESTED", refundEnv.getEvent_type());
        assertEquals("P0", refundEnv.getPriority());
        assertEquals(1, cashierFrames.size());
        assertTrue(cashierFrames.get(0).contains("\"event_type\":\"REFUND_REQUESTED\""));
        // Customer session must NOT receive internal cashier REFUND_REQUESTED alert
        assertEquals(1, customerFrames.size());
    }

    @Test
    void activityPopupAnnouncementQueueCallAndRefundResultShouldPublishUnifiedEnvelopes() throws Exception {
        WebSocketOutboundDispatcher dispatcher = createSynchronousDispatcher();
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        UnifiedNotificationService notificationService = new UnifiedNotificationService(
                notificationMapper, registry, null);

        List<String> customerFrames = new ArrayList<>();
        WebSocketSession customerSession = createRecordingSession("mp-cust-multi", customerFrames);
        registry.register(customerSession, "MINI_PROGRAM", 1, "openid_queue_user", null, null, null);

        // 1. Marketing Activity Popup Published (P2, MODAL_POPUP_OR_INVALIDATE)
        ActivityPopup popup = new ActivityPopup();
        popup.setId(501L);
        popup.setName("周末全场8折狂欢海报");
        popup.setPopup_image("/upload/activity/weekend_80.png");
        popup.setImage_url("/pages/order/order");
        popup.setTarget_user("all");
        popup.setType("page_activity");
        popup.setIs_enabled(1);
        popup.setApply_shop_ids("[1]");

        UnifiedMessageEnvelope popupEnv = notificationService.publishActivityPopupChanged("ADDED", popup);
        assertNotNull(popupEnv);
        assertEquals("MARKETING", popupEnv.getBusiness_type());
        assertEquals("ACTIVITY_POPUP_CHANGED", popupEnv.getEvent_type());
        assertEquals("P2", popupEnv.getPriority());
        assertEquals("MODAL_POPUP_OR_INVALIDATE", popupEnv.getDisplay_strategy().getUi_type());
        assertEquals("周末全场8折狂欢海报", popupEnv.getPayload().get("name"));

        // 2. Store Announcement Published (P2, TOP_NOTICE_BAR)
        Announcement announcement = new Announcement();
        announcement.setId(601L);
        announcement.setShop_id(1);
        announcement.setTitle("今日特色：现熬酸梅汤免费续杯");
        announcement.setContent("堂食顾客均可免费无限续杯");
        announcement.setStatus(1);

        UnifiedMessageEnvelope annEnv = notificationService.publishShopAnnouncementChanged("PUBLISHED", announcement);
        assertNotNull(annEnv);
        assertEquals("SHOP", annEnv.getBusiness_type());
        assertEquals("SHOP_ANNOUNCEMENT_CHANGED", annEnv.getEvent_type());
        assertEquals("P2", annEnv.getPriority());
        assertEquals("TOP_NOTICE_BAR", annEnv.getDisplay_strategy().getUi_type());

        // 3. Queue Ticket Called (P0, USER-targeted TOP_BANNER_AND_VIBRATE)
        QueueTicket ticket = new QueueTicket();
        ticket.setId(701L);
        ticket.setShop_id(1);
        ticket.setTicket_no("A108");
        ticket.setOpenid("openid_queue_user");
        ticket.setParty_size(4);
        ticket.setDine_type("堂食");
        ticket.setStatus("calling");

        UnifiedMessageEnvelope queueEnv = notificationService.publishQueueTicketCalled(ticket, 0, "总店");
        assertNotNull(queueEnv);
        assertEquals("QUEUE", queueEnv.getBusiness_type());
        assertEquals("QUEUE_TICKET_CALLED", queueEnv.getEvent_type());
        assertEquals("P0", queueEnv.getPriority());
        assertEquals("TOP_BANNER_AND_VIBRATE", queueEnv.getDisplay_strategy().getUi_type());
        assertEquals("A108", queueEnv.getPayload().get("ticket_no"));

        // 4. Customer Order Refund Result (P1, USER-targeted TOP_BANNER)
        Order refundOrder = new Order();
        refundOrder.setId(801);
        refundOrder.setOrder_no("ORD_REF_801");
        refundOrder.setShop_id(1);
        refundOrder.setOpenid("openid_queue_user");

        UnifiedMessageEnvelope refundResEnv = notificationService.publishCustomerOrderRefundResult(
                refundOrder, "APPROVED", 36.5, "商家已同意退款，原路退回微信支付");
        assertNotNull(refundResEnv);
        assertEquals("ORDER", refundResEnv.getBusiness_type());
        assertEquals("ORDER_REFUND_PROCESSED", refundResEnv.getEvent_type());
        assertEquals("P1", refundResEnv.getPriority());
        assertEquals("TOP_BANNER", refundResEnv.getDisplay_strategy().getUi_type());

        assertEquals(4, customerFrames.size());
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
