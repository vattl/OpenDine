package com.lanf.realtime;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.event.KdsDeviceCredentialChangedEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.io.IOException;

/**
 * KDS 厨显 WebSocket：按 (shopId, screenTag) 分桶推送。
 */
@Component
public class KdsWebSocketHub {

    private static final Logger log = LoggerFactory.getLogger(KdsWebSocketHub.class);
    private static final ObjectMapper JSON = new ObjectMapper();

    private final Map<String, Set<WebSocketSession>> buckets = new ConcurrentHashMap<>();
    private final WebSocketOutboundDispatcher outbound;

    public KdsWebSocketHub(WebSocketOutboundDispatcher outbound) {
        this.outbound = outbound;
    }

    public void register(WebSocketSession session, int shopId, String screenTag) {
        String key = bucketKey(shopId, screenTag);
        buckets.computeIfAbsent(key, k -> ConcurrentHashMap.newKeySet()).add(session);
        outbound.register(session);
        session.getAttributes().put("kds_bucket", key);
        Object ver = session.getAttributes().get("kds_protocol_version");
        int protocolVersion = (ver instanceof Number) ? ((Number) ver).intValue() : 1;
        log.info("[ws/kds] connected shop={} screen={} v={} id={}", shopId, screenTag, protocolVersion, session.getId());
    }

    public void unregister(WebSocketSession session) {
        outbound.unregister(session);
        Object key = session.getAttributes().get("kds_bucket");
        if (key instanceof String) {
            buckets.computeIfPresent((String) key, (k, set) -> {
                set.remove(session);
                return set.isEmpty() ? null : set;
            });
        }
        log.info("[ws/kds] closed id={}", session.getId());
    }

    @EventListener
    public void closeRevokedDeviceSessions(KdsDeviceCredentialChangedEvent event) {
        if (event == null || event.getDeviceCode() == null) {
            return;
        }
        for (Set<WebSocketSession> sessions : buckets.values()) {
            for (WebSocketSession session : sessions.toArray(new WebSocketSession[0])) {
                Object shop = session.getAttributes().get("kds_shop_id");
                Object deviceCode = session.getAttributes().get("kds_device_code");
                if (!(shop instanceof Number)
                        || ((Number) shop).intValue() != event.getShopId()
                        || !event.getDeviceCode().equals(deviceCode)) {
                    continue;
                }
                unregister(session);
                try {
                    if (session.isOpen()) {
                        session.close(CloseStatus.POLICY_VIOLATION.withReason("device credential changed"));
                    }
                } catch (IOException ex) {
                    log.debug("[ws/kds] credential-change close failed id={}: {}", session.getId(), ex.getMessage());
                }
            }
        }
    }

    public int broadcast(int shopId, String screenTag, String json) {
        return broadcastToBucket(bucketKey(shopId, screenTag), json, null);
    }

    /** 仅推向 V1 协议老客户端（/ws/kds） */
    public int broadcastV1(int shopId, String screenTag, String json) {
        return broadcastToBucket(bucketKey(shopId, screenTag), json, 1);
    }

    /** 仅推向 V2 协议新客户端（/ws/kds/v2） */
    public int broadcastV2(int shopId, String screenTag, String json) {
        return broadcastToBucket(bucketKey(shopId, screenTag), json, 2);
    }

    /** 总出餐屏等：向同店多屏广播 */
    public void broadcastShop(int shopId, String json, String... screenTags) {
        if (screenTags == null || screenTags.length == 0) {
            return;
        }
        for (String tag : screenTags) {
            broadcast(shopId, tag, json);
        }
    }

    private int broadcastToBucket(String key, String json, Integer targetVersion) {
        Set<WebSocketSession> set = buckets.get(key);
        if (set == null || set.isEmpty()) {
            log.debug("[ws/kds] no subscriber bucket={}", key);
            return 0;
        }
        TextMessage msg = new TextMessage(json);
        String acknowledgementKey = targetVersion != null && targetVersion == 2
                ? acknowledgementKey(json) : null;
        List<WebSocketSession> snapshot = new ArrayList<>(set);
        int sent = 0;
        for (WebSocketSession s : snapshot) {
            try {
                if (s != null && s.isOpen()) {
                    if (targetVersion != null) {
                        Object verObj = s.getAttributes().get("kds_protocol_version");
                        int sessionVersion = (verObj instanceof Number) ? ((Number) verObj).intValue() : 1;
                        if (sessionVersion != targetVersion.intValue()) {
                            continue;
                        }
                    }
                    boolean accepted = acknowledgementKey == null
                            ? outbound.dispatch(s, msg)
                            : outbound.dispatchAcknowledged(s, msg, acknowledgementKey);
                    if (accepted) sent++;
                } else {
                    set.remove(s);
                }
            } catch (RuntimeException e) {
                log.warn("[ws/kds] enqueue failed bucket={}: {}", key, e.getMessage());
                set.remove(s);
            }
        }
        if (sent == 0) {
            log.debug("[ws/kds] bucket={} had sessions but none open or matched version {}", key, targetVersion);
        }
        return sent;
    }

    private static String bucketKey(int shopId, String screenTag) {
        return shopId + ":" + (screenTag != null ? screenTag : "");
    }

    static String acknowledgementKey(String json) {
        try {
            JsonNode body = JSON.readTree(json);
            long eventSequence = body.path("event_seq").asLong(0);
            String eventId = body.path("event_id").asText("").trim();
            if (body.path("protocol_version").asInt() != 2 || eventSequence <= 0 || eventId.isEmpty()) {
                return null;
            }
            return eventSequence + ":" + eventId;
        } catch (IOException | RuntimeException ex) {
            return null;
        }
    }

    public int sessionCount() {
        return buckets.values().stream().mapToInt(Set::size).sum();
    }

    public int bucketCount() {
        return buckets.size();
    }
}
