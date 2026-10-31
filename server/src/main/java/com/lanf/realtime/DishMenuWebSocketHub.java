package com.lanf.realtime;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 维护点餐端 WebSocket 连接，并向全部在线客户端广播菜单变更。
 */
@Component
public class DishMenuWebSocketHub {

    private static final Logger log = LoggerFactory.getLogger(DishMenuWebSocketHub.class);

    private final Set<WebSocketSession> sessions = ConcurrentHashMap.newKeySet();
    private final WebSocketOutboundDispatcher outbound;

    public DishMenuWebSocketHub(WebSocketOutboundDispatcher outbound) {
        this.outbound = outbound;
    }

    public void register(WebSocketSession session) {
        sessions.add(session);
        outbound.register(session);
        log.info("[ws/menu] connected, id={}, total={}", session.getId(), sessions.size());
    }

    public void unregister(WebSocketSession session) {
        sessions.remove(session);
        outbound.unregister(session);
        log.info("[ws/menu] closed, id={}, total={}", session.getId(), sessions.size());
    }

    /**
     * 向所有已连接客户端推送 JSON 文本（UTF-8）。
     */
    public void broadcast(String json) {
        if (sessions.isEmpty()) {
            return;
        }
        List<WebSocketSession> snapshot = new ArrayList<>(sessions);
        for (WebSocketSession s : snapshot) {
            try {
                if (s != null && s.isOpen()) {
                    outbound.dispatch(s, new TextMessage(json));
                } else {
                    sessions.remove(s);
                }
            } catch (RuntimeException e) {
                log.warn("[ws/menu] enqueue failed, remove session {}: {}", s != null ? s.getId() : "null", e.getMessage());
                sessions.remove(s);
            }
        }
    }

    public int sessionCount() {
        return sessions.size();
    }
}
