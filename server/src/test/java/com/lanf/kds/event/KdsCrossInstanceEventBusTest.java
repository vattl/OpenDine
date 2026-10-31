package com.lanf.kds.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.service.KdsPushService;
import com.lanf.realtime.KdsWebSocketHub;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.connection.DefaultMessage;
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

class KdsCrossInstanceEventBusTest {

    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
    }

    @Test
    @DisplayName("publish sends serialized message to Redis topic")
    void publishSendsToRedisTopic() {
        KdsRedisEventBus bus = new KdsRedisEventBus();
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ReflectionTestUtils.setField(bus, "redisTemplate", redis);
        ReflectionTestUtils.setField(bus, "objectMapper", objectMapper);

        Map<String, Object> envelope = new HashMap<>();
        envelope.put("event_seq", 42L);
        envelope.put("event_id", "event-42");
        envelope.put("shop_id", 1);
        envelope.put("type", "order_updated");

        bus.publish(1, envelope);

        verify(redis, times(1)).convertAndSend(eq(KdsRedisEventBus.REDIS_CHANNEL), anyString());
    }

    @Test
    @DisplayName("publish survives Redis exceptions without throwing (resilient to bus failure)")
    void publishSurvivesRedisFailure() {
        KdsRedisEventBus bus = new KdsRedisEventBus();
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        doThrow(new RuntimeException("Redis connection refused"))
                .when(redis).convertAndSend(anyString(), anyString());
        ReflectionTestUtils.setField(bus, "redisTemplate", redis);
        ReflectionTestUtils.setField(bus, "objectMapper", objectMapper);

        Map<String, Object> envelope = new HashMap<>();
        envelope.put("event_seq", 42L);
        envelope.put("shop_id", 1);

        // Must not throw exception
        bus.publish(1, envelope);
    }

    @Test
    @DisplayName("onMessage invokes listeners for events from other instances, ignores own instance")
    void onMessageFiltersByInstanceId() throws Exception {
        KdsRedisEventBus bus = new KdsRedisEventBus();
        ReflectionTestUtils.setField(bus, "objectMapper", objectMapper);

        List<KdsCrossInstanceEventMessage> received = new ArrayList<>();
        bus.registerListener(received::add);

        // 1. Message from another instance -> received
        KdsCrossInstanceEventMessage remoteMsg = new KdsCrossInstanceEventMessage(
                "other-instance-uuid",
                1,
                100L,
                "event-100",
                "{\"protocol_version\":2}",
                System.currentTimeMillis()
        );
        String remoteJson = objectMapper.writeValueAsString(remoteMsg);
        Message message = new DefaultMessage(
                KdsRedisEventBus.REDIS_CHANNEL.getBytes(StandardCharsets.UTF_8),
                remoteJson.getBytes(StandardCharsets.UTF_8)
        );
        bus.onMessage(message, null);

        assertEquals(1, received.size());
        assertEquals("other-instance-uuid", received.get(0).getOriginInstanceId());
        assertEquals(100L, received.get(0).getEventSeq());

        // 2. Message from own instance -> ignored
        KdsCrossInstanceEventMessage selfMsg = new KdsCrossInstanceEventMessage(
                bus.getInstanceId(),
                1,
                101L,
                "event-101",
                "{\"protocol_version\":2}",
                System.currentTimeMillis()
        );
        String selfJson = objectMapper.writeValueAsString(selfMsg);
        Message selfMessage = new DefaultMessage(
                KdsRedisEventBus.REDIS_CHANNEL.getBytes(StandardCharsets.UTF_8),
                selfJson.getBytes(StandardCharsets.UTF_8)
        );
        bus.onMessage(selfMessage, null);

        // Still only 1 received
        assertEquals(1, received.size());
    }

    @Test
    @DisplayName("KdsPushService broadcasts remote events and deduplicates identical event sequence")
    void pushServiceDispatchesAndDeduplicatesRemoteEvents() {
        KdsPushService pushService = new KdsPushService();
        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        KdsCrossInstanceEventBus bus = mock(KdsCrossInstanceEventBus.class);

        ReflectionTestUtils.setField(pushService, "hub", hub);
        ReflectionTestUtils.setField(pushService, "eventBus", bus);
        ReflectionTestUtils.setField(pushService, "objectMapper", objectMapper);

        KdsCrossInstanceEventMessage remoteMsg = new KdsCrossInstanceEventMessage(
                "other-instance",
                1,
                55L,
                "event-55",
                "{\"type\":\"order_updated\",\"event_seq\":55}",
                System.currentTimeMillis()
        );

        // First delivery: broadcasts to hub
        pushService.handleRemoteEvent(remoteMsg);
        verify(hub, times(KdsScreenTag.allBroadcastTags().size())).broadcastV2(eq(1), anyString(), eq(remoteMsg.getEnvelopeJson()));

        // Second delivery (duplicate): should be deduplicated and not broadcast to hub again
        pushService.handleRemoteEvent(remoteMsg);
        verify(hub, times(KdsScreenTag.allBroadcastTags().size())).broadcastV2(eq(1), anyString(), eq(remoteMsg.getEnvelopeJson()));
    }

    @Test
    @DisplayName("KdsPushService broadcastV2Envelope publishes to local hub and cross-instance bus")
    void broadcastV2EnvelopePublishesToBus() {
        KdsPushService pushService = new KdsPushService();
        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        KdsCrossInstanceEventBus bus = mock(KdsCrossInstanceEventBus.class);

        ReflectionTestUtils.setField(pushService, "hub", hub);
        ReflectionTestUtils.setField(pushService, "eventBus", bus);
        ReflectionTestUtils.setField(pushService, "objectMapper", objectMapper);

        Map<String, Object> envelope = new HashMap<>();
        envelope.put("event_seq", 88L);
        envelope.put("event_id", "event-88");
        envelope.put("shop_id", 2);
        envelope.put("type", "order_accepted");

        pushService.broadcastV2Envelope(2, envelope);

        // Broadcasts to local hub tags
        verify(hub, times(KdsScreenTag.allBroadcastTags().size())).broadcastV2(eq(2), anyString(), anyString());
        // Publishes to cross-instance bus
        verify(bus, times(1)).publish(eq(2), eq(envelope));
    }
}
