package com.lanf.config;

import com.lanf.realtime.DishMenuWebSocketHandler;
import com.lanf.realtime.KdsWebSocketHandler;
import com.lanf.realtime.CashierEventWebSocketHandler;
import com.lanf.realtime.UnifiedNotificationWebSocketHandler;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * 菜品菜单实时推送：路径 /ws/menu；统一实时消息通道：路径 /ws/v1/notify。
 * 小程序需在后台配置 socket 合法域名（wss），与 https 业务域一致。
 */
@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    @Autowired
    private DishMenuWebSocketHandler dishMenuWebSocketHandler;
    @Autowired
    private KdsWebSocketHandler kdsWebSocketHandler;
    @Autowired
    private CashierEventWebSocketHandler cashierEventWebSocketHandler;
    @Autowired(required = false)
    private UnifiedNotificationWebSocketHandler unifiedNotificationWebSocketHandler;

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(dishMenuWebSocketHandler, "/ws/menu")
                .setAllowedOrigins("*");
        registry.addHandler(kdsWebSocketHandler, "/ws/kds", "/ws/kds/v2")
                .setAllowedOrigins("*");
        registry.addHandler(cashierEventWebSocketHandler, "/ws/cashier-events")
                .setAllowedOrigins("*");
        if (unifiedNotificationWebSocketHandler != null) {
            registry.addHandler(unifiedNotificationWebSocketHandler, "/ws/v1/notify")
                    .setAllowedOrigins("*");
        }
    }
}
