package com.lanf.realtime;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.net.URI;
import java.io.IOException;
import java.util.Map;

/**
 * 厨显连接：wss://host/ws/kds?shop_id=1&screen_tag=meat_grill&token=...
 */
@Component
public class KdsWebSocketHandler extends TextWebSocketHandler {

    private static final ObjectMapper JSON = new ObjectMapper();

    @Autowired
    private KdsWebSocketHub hub;
    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private WebSocketOutboundDispatcher outbound;

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        Map<String, String> params = parseQuery(session.getUri());
        String token = params.get("token");
        if (!StringUtils.hasText(token) && session.getHandshakeHeaders() != null) {
            token = session.getHandshakeHeaders().getFirst("X-Kds-Device-Token");
        }
        if (!StringUtils.hasText(token)) {
            session.close(CloseStatus.POLICY_VIOLATION.withReason("missing token"));
            return;
        }
        KdsDevice device = deviceService.findByToken(token.trim());
        if (device == null) {
            session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid token"));
            return;
        }
        String screenTag = params.get("screen_tag");
        if (!StringUtils.hasText(screenTag)) {
            screenTag = device.getScreen_tag();
        }
        if (!screenTag.equals(device.getScreen_tag())) {
            session.close(CloseStatus.POLICY_VIOLATION.withReason("screen_tag mismatch"));
            return;
        }
        int shopId = device.getShop_id();
        String shopParam = params.get("shop_id");
        if (StringUtils.hasText(shopParam)) {
            try {
                int reqShop = Integer.parseInt(shopParam.trim());
                if (reqShop != shopId) {
                    session.close(CloseStatus.POLICY_VIOLATION.withReason("shop_id mismatch"));
                    return;
                }
            } catch (NumberFormatException invalidShop) {
                session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid shop_id"));
                return;
            }
        }
        String shopHeader = session.getHandshakeHeaders() == null
                ? null : session.getHandshakeHeaders().getFirst("X-Shop-Id");
        if (StringUtils.hasText(shopHeader)) {
            try {
                if (Integer.parseInt(shopHeader.trim()) != shopId) {
                    session.close(CloseStatus.POLICY_VIOLATION.withReason("X-Shop-Id mismatch"));
                    return;
                }
            } catch (NumberFormatException invalidShop) {
                session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid X-Shop-Id"));
                return;
            }
        }
        session.getAttributes().put("kds_shop_id", shopId);
        session.getAttributes().put("kds_device_code", device.getDevice_code());
        if (device.getToken_expires_at() != null) {
            session.getAttributes().put("kds_token_expires_at_ms", device.getToken_expires_at().getTime());
        }
        session.getAttributes().put("kds_screen_tag", screenTag);
        URI uri = session.getUri();
        boolean isV2 = uri != null && uri.getPath() != null && uri.getPath().contains("/v2");
        String pVer = params.get("protocol_version");
        if ("2".equals(pVer)) {
            isV2 = true;
        }
        session.getAttributes().put("kds_protocol_version", isV2 ? 2 : 1);
        hub.register(session, shopId, screenTag);
        deviceService.heartbeat(device.getDevice_code());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        hub.unregister(session);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        if (message != null && "ping".equalsIgnoreCase(message.getPayload().trim())) {
            Object expiresAt = session.getAttributes().get("kds_token_expires_at_ms");
            if (expiresAt instanceof Number && ((Number) expiresAt).longValue() <= System.currentTimeMillis()) {
                hub.unregister(session);
                session.close(CloseStatus.POLICY_VIOLATION.withReason("token expired"));
                return;
            }
            outbound.dispatch(session, new TextMessage("{\"type\":\"pong\"}"));
            return;
        }
        if (message == null) return;
        try {
            JsonNode body = JSON.readTree(message.getPayload());
            Object sessionVersion = session.getAttributes().get("kds_protocol_version");
            if (body != null && sessionVersion instanceof Number
                    && ((Number) sessionVersion).intValue() == 2
                    && "ack".equals(body.path("type").asText())
                    && body.path("protocol_version").asInt() == 2
                    && body.path("event_seq").canConvertToLong()
                    && body.path("event_seq").asLong() > 0
                    && !body.path("event_id").asText().trim().isEmpty()) {
                outbound.acknowledge(session, body.path("event_seq").asLong() + ":"
                        + body.path("event_id").asText().trim());
            }
        } catch (IOException | RuntimeException ignore) {
            // Unknown client messages do not participate in the acknowledgement contract.
        }
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        hub.unregister(session);
    }

    private static Map<String, String> parseQuery(URI uri) {
        Map<String, String> m = new java.util.HashMap<>();
        if (uri == null || uri.getQuery() == null) {
            return m;
        }
        for (String part : uri.getQuery().split("&")) {
            int eq = part.indexOf('=');
            if (eq > 0) {
                try {
                    m.put(part.substring(0, eq), java.net.URLDecoder.decode(part.substring(eq + 1), "UTF-8"));
                } catch (java.io.UnsupportedEncodingException e) {
                    m.put(part.substring(0, eq), part.substring(eq + 1));
                }
            }
        }
        return m;
    }
}
