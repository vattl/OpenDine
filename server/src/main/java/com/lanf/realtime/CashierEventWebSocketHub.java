package com.lanf.realtime;

import com.lanf.notify.service.UnifiedNotificationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class CashierEventWebSocketHub {
    private static final Logger log = LoggerFactory.getLogger(CashierEventWebSocketHub.class);
    private final ConcurrentHashMap<Integer, Set<WebSocketSession>> sessions = new ConcurrentHashMap<>();
    private final WebSocketOutboundDispatcher outbound;
    @Autowired(required = false)
    private UnifiedNotificationService unifiedNotificationService;

    public CashierEventWebSocketHub(WebSocketOutboundDispatcher outbound) {
        this.outbound = outbound;
    }

    public void setUnifiedNotificationService(UnifiedNotificationService unifiedNotificationService) {
        this.unifiedNotificationService = unifiedNotificationService;
    }

    public Set<Integer> activeShops() {
        Set<Integer> active = new java.util.HashSet<>();
        sessions.forEach((shop,bucket) -> { if (!bucket.isEmpty()) active.add(shop); });
        return active;
    }
    public void register(int shopId, WebSocketSession session) {
        sessions.computeIfAbsent(shopId, ignored -> ConcurrentHashMap.newKeySet()).add(session);
        outbound.register(session);
        session.getAttributes().put("cashier_event_shop", shopId);
    }
    public void unregister(WebSocketSession session) {
        Object shop = session.getAttributes().get("cashier_event_shop");
        if (shop instanceof Integer && sessions.containsKey(shop)) sessions.get(shop).remove(session);
        outbound.unregister(session);
    }
    public void broadcastWake(int shopId, long headCursor) {
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishKdsDeliveryAvailable(shopId, headCursor);
            } catch (Exception ex) {
                log.warn("[ws/cashier-events] unified bridge wake failed shop={}: {}", shopId, ex.getMessage());
            }
        }
        Set<WebSocketSession> bucket = sessions.get(shopId);
        if (bucket == null) return;
        TextMessage message = new TextMessage("{\"type\":\"kds_delivery_available\",\"headCursor\":" + headCursor + "}");
        for (WebSocketSession session : bucket.toArray(new WebSocketSession[0])) {
            try {
                if (!session.isOpen()) { bucket.remove(session); continue; }
                outbound.dispatch(session, message);
            } catch (Exception ex) {
                bucket.remove(session); log.warn("[ws/cashier-events] wake failed shop={} id={}: {}", shopId, session.getId(), ex.getMessage());
            }
        }
    }
    public void broadcastTableOrderChanged(int shopId, String tableNumber, String orderNo, int diners) {
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishTableOrderChanged(shopId, tableNumber, orderNo, diners);
            } catch (Exception ex) {
                log.warn("[ws/cashier-events] unified bridge table_order_changed failed shop={}: {}", shopId, ex.getMessage());
            }
        }
        Set<WebSocketSession> bucket = sessions.get(shopId);
        if (bucket == null) return;
        String json = String.format("{\"type\":\"table_order_changed\",\"shopId\":%d,\"tableNumber\":\"%s\",\"orderNo\":\"%s\",\"diners\":%d}",
                shopId,
                tableNumber != null ? tableNumber.replace("\"", "\\\"") : "",
                orderNo != null ? orderNo.replace("\"", "\\\"") : "",
                diners);
        TextMessage message = new TextMessage(json);
        for (WebSocketSession session : bucket.toArray(new WebSocketSession[0])) {
            try {
                if (!session.isOpen()) { bucket.remove(session); continue; }
                outbound.dispatch(session, message);
            } catch (Exception ex) {
                bucket.remove(session);
                log.warn("[ws/cashier-events] table_order_changed broadcast failed shop={} id={}: {}", shopId, session.getId(), ex.getMessage());
            }
        }
    }
}
