package com.lanf.realtime;

import com.lanf.kds.delivery.CashierKdsLeaseService;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.net.URI;
import java.net.URLDecoder;
import java.util.HashMap;
import java.util.Map;

@Component
public class CashierEventWebSocketHandler extends TextWebSocketHandler {
    private final CashierKdsLeaseService leaseService;
    private final CashierEventWebSocketHub hub;
    private final WebSocketOutboundDispatcher outbound;
    public CashierEventWebSocketHandler(CashierKdsLeaseService leaseService, CashierEventWebSocketHub hub,
                                        WebSocketOutboundDispatcher outbound) {
        this.leaseService = leaseService; this.hub = hub; this.outbound = outbound;
    }
    @Override public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        try {
            Map<String,String> q = query(session.getUri());
            String shop = first(session, "X-Shop-Id", q.get("shop_id"));
            String device = first(session, "X-Cashier-Device-Code", q.get("device_code"));
            String epochValue = first(session, "X-Cashier-Authority-Epoch", q.get("authority_epoch"));
            String token = first(session, "X-Cashier-Lease-Token", q.get("lease_token"));
            int shopId = Integer.parseInt(shop); long epoch = Long.parseLong(epochValue);
            leaseService.validate(shopId, device, epoch, token);
            hub.register(shopId, session);
            outbound.dispatch(session, new TextMessage("{\"type\":\"connected\"}"));
        } catch (Exception ex) { session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid cashier KDS lease")); }
    }
    @Override public void afterConnectionClosed(WebSocketSession session, CloseStatus status) { hub.unregister(session); }
    @Override public void handleTransportError(WebSocketSession session, Throwable exception) { hub.unregister(session); }
    @Override protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        if ("ping".equalsIgnoreCase(message.getPayload().trim())) {
            outbound.dispatch(session, new TextMessage("{\"type\":\"pong\"}"));
        }
    }
    private static Map<String,String> query(URI uri) throws Exception {
        Map<String,String> values = new HashMap<>();
        if (uri == null || uri.getQuery() == null) return values;
        for (String item : uri.getQuery().split("&")) {
            int i = item.indexOf('='); if (i > 0) values.put(item.substring(0,i), URLDecoder.decode(item.substring(i+1), "UTF-8"));
        }
        return values;
    }
    private static String first(WebSocketSession session, String header, String fallback) {
        String value = session.getHandshakeHeaders().getFirst(header);
        return value == null || value.trim().isEmpty() ? fallback : value.trim();
    }
}
