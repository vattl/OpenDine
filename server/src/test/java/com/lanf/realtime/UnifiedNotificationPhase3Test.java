package com.lanf.realtime;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.controller.NotificationChannelController;
import com.lanf.entity.R;
import com.lanf.entity.RealtimeNotification;
import com.lanf.mapper.RealtimeNotificationMapper;
import com.lanf.notify.service.NotificationRetentionCleanupScheduler;
import com.lanf.notify.service.ShopNotificationConfigService;
import com.lanf.notify.service.UnifiedNotificationService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.socket.WebSocketSession;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 第三阶段：实时消息通道监控统计、联调测试推送与过期通知清理测试。
 */
class UnifiedNotificationPhase3Test {

    @Test
    void channelStatsTestPushAndRetentionCleanupShouldWorkEndToEnd() {
        WebSocketOutboundDispatcher dispatcher = mock(WebSocketOutboundDispatcher.class);
        UnifiedSessionRegistry registry = new UnifiedSessionRegistry(dispatcher);
        RealtimeNotificationMapper notificationMapper = mock(RealtimeNotificationMapper.class);
        ShopNotificationConfigService configService = mock(ShopNotificationConfigService.class);

        when(notificationMapper.selectCount(any(QueryWrapper.class))).thenReturn(2);
        when(notificationMapper.delete(any(QueryWrapper.class))).thenReturn(5);
        when(notificationMapper.insert(any(RealtimeNotification.class))).thenAnswer(inv -> {
            RealtimeNotification entity = inv.getArgument(0);
            entity.setSeq_id(301L);
            return 1;
        });

        WebSocketSession cashierSession = mock(WebSocketSession.class);
        Map<String, Object> attrs = new ConcurrentHashMap<>();
        when(cashierSession.getId()).thenReturn("sess-cashier-1");
        when(cashierSession.isOpen()).thenReturn(true);
        when(cashierSession.getAttributes()).thenReturn(attrs);
        registry.register(cashierSession, UnifiedSessionRegistry.CLIENT_TYPE_CASHIER, 1, null, null, 10, "POS-01");

        UnifiedNotificationService service = new UnifiedNotificationService(
                notificationMapper, registry, null);
        NotificationChannelController controller = new NotificationChannelController(service, configService);

        MockHttpServletRequest req = new MockHttpServletRequest("GET", "/admin/notifications/channel-stats");
        req.addHeader("X-Shop-Id", "1");
        R statsResp = controller.getChannelStats(1, null, req);
        assertEquals(0, statsResp.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> stats = (Map<String, Object>) statsResp.get("data");
        assertNotNull(stats);
        assertEquals(1, stats.get("cashier_online_count"));
        assertEquals(2L, stats.get("pending_p0_count"));

        Map<String, Object> testBody = new HashMap<>();
        testBody.put("shop_id", 1);
        testBody.put("event_type", "ORDER_PREP_TIMEOUT");
        R pushResp = controller.triggerTestPush(testBody, req);
        assertEquals(0, pushResp.get("code"));
        UnifiedMessageEnvelope pushed = (UnifiedMessageEnvelope) pushResp.get("data");
        assertNotNull(pushed);
        assertEquals("ORDER_PREP_TIMEOUT", pushed.getEvent_type());
        assertEquals("P0", pushed.getPriority());

        NotificationRetentionCleanupScheduler cleanupScheduler = new NotificationRetentionCleanupScheduler(service);
        int deleted = cleanupScheduler.purgeExpiredAndArchivedNotifications();
        assertEquals(5, deleted);

        Map<String, Object> cleanupReq = new HashMap<>();
        cleanupReq.put("retention_days", 7);
        R cleanupResp = controller.cleanupNotifications(cleanupReq);
        assertEquals(0, cleanupResp.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> cleanupData = (Map<String, Object>) cleanupResp.get("data");
        assertTrue(((Number) cleanupData.get("deleted_count")).intValue() >= 0);
    }
}
