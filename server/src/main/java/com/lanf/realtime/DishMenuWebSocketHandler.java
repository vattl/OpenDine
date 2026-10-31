package com.lanf.realtime;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * C 端 / 小程序连接：wx.connectSocket({ url: 'wss://域名/ws/menu' })。
 * 消息 type：dish_catalog_changed（宜重拉 GET /dish/listAll）、business_changed（business 布尔）、auto_accept_changed（enabled 布尔）。
 */
@Component
public class DishMenuWebSocketHandler extends TextWebSocketHandler {

    @Autowired
    private DishMenuWebSocketHub hub;

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        hub.register(session);
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        hub.unregister(session);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) {
        // 客户端可发 ping；可选应答，非必须
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        hub.unregister(session);
    }
}
