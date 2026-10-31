package com.lanf.kds.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.connection.MessageListener;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.listener.ChannelTopic;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Redis Pub/Sub implementation of KdsCrossInstanceEventBus.
 * Distributes V2 realtime envelopes to all active cloud server instances.
 * Fault-tolerant: Redis outages never disrupt local execution or DB transactions.
 */
@Component
public class KdsRedisEventBus implements KdsCrossInstanceEventBus, MessageListener {

    private static final Logger log = LoggerFactory.getLogger(KdsRedisEventBus.class);
    public static final String REDIS_CHANNEL = "kds:events:broadcast";

    private final String instanceId = UUID.randomUUID().toString();
    private final List<KdsCrossInstanceEventListener> listeners = new CopyOnWriteArrayList<>();

    @Autowired(required = false)
    private StringRedisTemplate redisTemplate;

    @Autowired(required = false)
    private RedisConnectionFactory connectionFactory;

    @Autowired
    private ObjectMapper objectMapper;

    private RedisMessageListenerContainer listenerContainer;

    @PostConstruct
    public void init() {
        if (connectionFactory != null) {
            try {
                listenerContainer = new RedisMessageListenerContainer();
                listenerContainer.setConnectionFactory(connectionFactory);
                listenerContainer.addMessageListener(this, new ChannelTopic(REDIS_CHANNEL));
                listenerContainer.afterPropertiesSet();
                listenerContainer.start();
                log.info("[kds/bus] Redis event bus initialized for instance={}", instanceId);
            } catch (Exception e) {
                log.warn("[kds/bus] Failed to start Redis listener container (falling back to local): {}", e.getMessage());
            }
        } else {
            log.info("[kds/bus] No Redis connectionFactory available; operating in local mode for instance={}", instanceId);
        }
    }

    @PreDestroy
    public void destroy() {
        if (listenerContainer != null) {
            try {
                listenerContainer.stop();
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    public String getInstanceId() {
        return instanceId;
    }

    @Override
    public void publish(int shopId, Map<String, Object> envelope) {
        if (envelope == null) return;
        try {
            Long eventSeq = null;
            Object seqObj = envelope.get("event_seq");
            if (seqObj instanceof Number) {
                eventSeq = ((Number) seqObj).longValue();
            }
            String eventId = (String) envelope.get("event_id");
            String json = objectMapper.writeValueAsString(envelope);
            KdsCrossInstanceEventMessage msg = new KdsCrossInstanceEventMessage(
                    instanceId,
                    shopId,
                    eventSeq,
                    eventId,
                    json,
                    System.currentTimeMillis()
            );
            if (redisTemplate != null) {
                String payload = objectMapper.writeValueAsString(msg);
                redisTemplate.convertAndSend(REDIS_CHANNEL, payload);
            }
        } catch (Exception e) {
            // Invariant: Event bus failure must NEVER break database cursor compensation or transaction
            log.warn("[kds/bus] Cross-instance event publish failed for shop={}: {}", shopId, e.getMessage());
        }
    }

    @Override
    public void registerListener(KdsCrossInstanceEventListener listener) {
        if (listener != null && !listeners.contains(listener)) {
            listeners.add(listener);
        }
    }

    @Override
    public void onMessage(Message message, byte[] pattern) {
        if (message == null || message.getBody() == null) return;
        try {
            String json = new String(message.getBody(), StandardCharsets.UTF_8);
            KdsCrossInstanceEventMessage eventMsg = objectMapper.readValue(json, KdsCrossInstanceEventMessage.class);
            if (eventMsg == null || instanceId.equals(eventMsg.getOriginInstanceId())) {
                // Ignore self-published events
                return;
            }
            for (KdsCrossInstanceEventListener listener : listeners) {
                try {
                    listener.onEvent(eventMsg);
                } catch (Exception ex) {
                    log.error("[kds/bus] Error notifying event listener: {}", ex.getMessage(), ex);
                }
            }
        } catch (Exception e) {
            log.warn("[kds/bus] Failed to deserialize cross-instance message: {}", e.getMessage());
        }
    }
}
