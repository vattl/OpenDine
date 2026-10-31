package com.lanf.realtime;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.delivery.CashierKdsLeaseService;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.security.JwtTokenService;
import io.jsonwebtoken.Claims;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.net.URI;
import java.net.URLDecoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 统一实时消息通道 WebSocket 处理器（端点：/ws/v1/notify）。
 * 支持：
 * 1. 收银端（CASHIER，支持管理员 JWT 或收银 KDS 租约鉴权）与小程序端（MINI_PROGRAM，按 shop_id + openid 绑定）
 * 2. PING / PONG 应用层心跳与服务端最新 seq_id 游标下发
 * 3. ACK 消息确认与跨终端告警消除
 * 4. BIND_CONTEXT 运行时动态切换门店或登录用户上下文
 */
@Component
public class UnifiedNotificationWebSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(UnifiedNotificationWebSocketHandler.class);

    private final UnifiedSessionRegistry sessionRegistry;
    private final UnifiedNotificationService notificationService;
    private final JwtTokenService jwtTokenService;
    private final CashierKdsLeaseService cashierKdsLeaseService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Autowired
    public UnifiedNotificationWebSocketHandler(UnifiedSessionRegistry sessionRegistry,
                                               UnifiedNotificationService notificationService,
                                               @Autowired(required = false) JwtTokenService jwtTokenService,
                                               @Autowired(required = false) CashierKdsLeaseService cashierKdsLeaseService) {
        this.sessionRegistry = sessionRegistry;
        this.notificationService = notificationService;
        this.jwtTokenService = jwtTokenService;
        this.cashierKdsLeaseService = cashierKdsLeaseService;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        try {
            Map<String, String> q = parseQuery(session.getUri());
            String rawClientType = firstNonBlank(
                    header(session, "X-Client-Type"),
                    q.get("client_type"),
                    q.get("clientType"),
                    UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM);
            String clientType = UnifiedSessionRegistry.normalizeClientType(rawClientType);

            Integer shopId = parseIntOrNull(firstNonBlank(
                    header(session, "X-Shop-Id"),
                    q.get("shop_id"),
                    q.get("shopId")));
            String openid = firstNonBlank(
                    header(session, "X-Openid"),
                    q.get("openid"),
                    q.get("user_openid"));
            Integer userId = parseIntOrNull(firstNonBlank(q.get("user_id"), q.get("userId")));
            String deviceId = firstNonBlank(
                    header(session, "X-Device-Id"),
                    header(session, "X-Cashier-Device-Code"),
                    q.get("device_id"),
                    q.get("device_code"));

            Integer adminId = null;
            if (UnifiedSessionRegistry.CLIENT_TYPE_CASHIER.equals(clientType)) {
                adminId = authenticateCashierSession(session, q, shopId);
                if (adminId == null) {
                    session.close(CloseStatus.POLICY_VIOLATION.withReason("unauthorized cashier session"));
                    return;
                }
                if (shopId == null || shopId <= 0) {
                    shopId = 1;
                }
            } else {
                String rawUserToken = firstNonBlank(
                        header(session, "X-User-Token"),
                        q.get("user_token"),
                        q.get("token"));
                if (StringUtils.hasText(rawUserToken)) {
                    String verifiedOpenid = authenticateMiniProgramToken(rawUserToken);
                    if (!StringUtils.hasText(verifiedOpenid)) {
                        session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid mini program user token"));
                        return;
                    }
                    if (StringUtils.hasText(openid) && !verifiedOpenid.equals(openid.trim())) {
                        session.close(CloseStatus.POLICY_VIOLATION.withReason("openid mismatch with user token"));
                        return;
                    }
                    openid = verifiedOpenid;
                }
            }

            sessionRegistry.register(session, clientType, shopId, openid, userId, adminId, deviceId);

            long headSeq = notificationService != null ? notificationService.currentServerHeadSeqId(shopId) : 0L;
            Map<String, Object> connectedPayload = new LinkedHashMap<>();
            connectedPayload.put("client_type", clientType);
            connectedPayload.put("shop_id", shopId);
            connectedPayload.put("openid", openid);
            connectedPayload.put("server_head_seq_id", headSeq);

            UnifiedMessageEnvelope connectedFrame = UnifiedMessageEnvelope.builder()
                    .frame_type("CONNECTED")
                    .message_id("sys_connected_" + session.getId())
                    .seq_id(headSeq)
                    .timestamp(System.currentTimeMillis())
                    .business_type("SYSTEM")
                    .event_type("CHANNEL_CONNECTED")
                    .priority("P3")
                    .require_ack(false)
                    .payload(connectedPayload)
                    .build();
            sessionRegistry.dispatchDirect(session, connectedFrame);
        } catch (Exception e) {
            log.warn("[ws/v1/notify] handshake failed session={}: {}", session.getId(), e.getMessage());
            session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid handshake"));
        }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        String raw = message != null && message.getPayload() != null ? message.getPayload().trim() : "";
        if (raw.isEmpty()) {
            return;
        }
        if ("ping".equalsIgnoreCase(raw)) {
            sendPong(session);
            return;
        }
        Map<String, Object> frame;
        try {
            frame = objectMapper.readValue(raw, new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            return;
        }
        String frameType = asString(frame.get("frame_type"));
        if (!StringUtils.hasText(frameType)) {
            frameType = asString(frame.get("type"));
        }
        if (!StringUtils.hasText(frameType)) {
            return;
        }
        String upperType = frameType.trim().toUpperCase();
        if ("PING".equals(upperType)) {
            sendPong(session);
        } else if ("ACK".equals(upperType)) {
            handleAckFrame(session, frame);
        } else if ("BIND_CONTEXT".equals(upperType)) {
            handleBindContextFrame(session, frame);
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        sessionRegistry.unregister(session);
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        sessionRegistry.unregister(session);
    }

    private void sendPong(WebSocketSession session) {
        Integer shopId = (Integer) session.getAttributes().get(UnifiedSessionRegistry.ATTR_SHOP_ID);
        long headSeq = notificationService != null ? notificationService.currentServerHeadSeqId(shopId) : 0L;
        Map<String, Object> pongPayload = new LinkedHashMap<>();
        pongPayload.put("server_head_seq_id", headSeq);

        UnifiedMessageEnvelope pong = UnifiedMessageEnvelope.builder()
                .frame_type("PONG")
                .message_id("sys_pong_" + System.currentTimeMillis())
                .seq_id(headSeq)
                .timestamp(System.currentTimeMillis())
                .business_type("SYSTEM")
                .event_type("HEARTBEAT_PONG")
                .priority("P3")
                .require_ack(false)
                .payload(pongPayload)
                .build();
        sessionRegistry.dispatchDirect(session, pong);
    }

    private void handleAckFrame(WebSocketSession session, Map<String, Object> frame) {
        Long seqId = parseLongOrNull(frame.get("seq_id"));
        if (seqId != null && seqId > 0) {
            sessionRegistry.acknowledgeSession(session, seqId);
        }
        List<String> messageIds = new ArrayList<>();
        String singleId = asString(frame.get("message_id"));
        if (StringUtils.hasText(singleId)) {
            messageIds.add(singleId.trim());
        }
        Object multiObj = frame.get("message_ids");
        if (multiObj instanceof List<?>) {
            for (Object item : (List<?>) multiObj) {
                if (item != null && StringUtils.hasText(item.toString())) {
                    messageIds.add(item.toString().trim());
                }
            }
        }
        Integer shopId = (Integer) session.getAttributes().get(UnifiedSessionRegistry.ATTR_SHOP_ID);
        String openid = (String) session.getAttributes().get(UnifiedSessionRegistry.ATTR_OPENID);
        String deviceId = (String) session.getAttributes().get(UnifiedSessionRegistry.ATTR_DEVICE_ID);
        Integer adminId = (Integer) session.getAttributes().get(UnifiedSessionRegistry.ATTR_ADMIN_ID);
        String ackedBy = StringUtils.hasText(deviceId) ? deviceId : (adminId != null ? "admin:" + adminId : "ws:" + session.getId());

        Map<String, Object> ackResult = notificationService != null
                ? notificationService.acknowledgeNotifications(shopId, openid, messageIds, ackedBy)
                : Collections.singletonMap("dismissed_message_ids", messageIds);

        UnifiedMessageEnvelope reply = UnifiedMessageEnvelope.builder()
                .frame_type("ACK_RESULT")
                .message_id("sys_ack_" + System.currentTimeMillis())
                .seq_id(seqId != null ? seqId : 0L)
                .timestamp(System.currentTimeMillis())
                .business_type("SYSTEM")
                .event_type("ACK_CONFIRMED")
                .priority("P3")
                .require_ack(false)
                .payload(ackResult)
                .build();
        sessionRegistry.dispatchDirect(session, reply);
    }

    private void handleBindContextFrame(WebSocketSession session, Map<String, Object> frame) throws Exception {
        Integer newShopId = parseIntOrNull(frame.get("shop_id") != null ? frame.get("shop_id").toString() : null);
        String newOpenid = asString(frame.get("openid"));
        Integer newUserId = parseIntOrNull(frame.get("user_id") != null ? frame.get("user_id").toString() : null);
        String token = firstNonBlank(asString(frame.get("user_token")), asString(frame.get("token")));
        if (StringUtils.hasText(token)) {
            String verifiedOpenid = authenticateMiniProgramToken(token);
            if (!StringUtils.hasText(verifiedOpenid)
                    || (StringUtils.hasText(newOpenid) && !verifiedOpenid.equals(newOpenid.trim()))) {
                session.close(CloseStatus.POLICY_VIOLATION.withReason("invalid bind_context user token"));
                return;
            }
            newOpenid = verifiedOpenid;
        }

        sessionRegistry.rebindContext(session, newShopId, newOpenid, newUserId);

        Integer effectiveShop = (Integer) session.getAttributes().get(UnifiedSessionRegistry.ATTR_SHOP_ID);
        String effectiveOpenid = (String) session.getAttributes().get(UnifiedSessionRegistry.ATTR_OPENID);
        long headSeq = notificationService != null ? notificationService.currentServerHeadSeqId(effectiveShop) : 0L;

        Map<String, Object> boundPayload = new LinkedHashMap<>();
        boundPayload.put("shop_id", effectiveShop);
        boundPayload.put("openid", effectiveOpenid);
        boundPayload.put("server_head_seq_id", headSeq);

        UnifiedMessageEnvelope boundFrame = UnifiedMessageEnvelope.builder()
                .frame_type("CONTEXT_BOUND")
                .message_id("sys_bound_" + System.currentTimeMillis())
                .seq_id(headSeq)
                .timestamp(System.currentTimeMillis())
                .business_type("SYSTEM")
                .event_type("CONTEXT_BOUND")
                .priority("P3")
                .require_ack(false)
                .payload(boundPayload)
                .build();
        sessionRegistry.dispatchDirect(session, boundFrame);
    }

    /**
     * 校验收银端连接鉴权（支持 B 端管理员 JWT 或 Cashier KDS Lease 令牌）。
     *
     * @return 验证通过时返回 adminId（租约模式返回 1），验证失败返回 null
     */
    private Integer authenticateCashierSession(WebSocketSession session, Map<String, String> q, Integer shopId) {
        String rawToken = firstNonBlank(
                header(session, "Authorization"),
                q.get("token"),
                q.get("access_token"));
        if (StringUtils.hasText(rawToken)) {
            String token = rawToken.trim();
            if (token.startsWith("Bearer ")) {
                token = token.substring(7).trim();
            }
            if (jwtTokenService != null && !token.isEmpty()) {
                try {
                    Claims claims = jwtTokenService.parseToken(token);
                    if (claims != null && "admin".equals(claims.getSubject()) && StringUtils.hasText(claims.getId())) {
                        return Integer.parseInt(claims.getId().trim());
                    }
                } catch (Exception e) {
                    log.debug("[ws/v1/notify] JWT validation failed: {}", e.getMessage());
                }
            }
        }
        // Fallback: Cashier KDS Lease validation (compatible with CashierEventWebSocketHandler)
        String device = firstNonBlank(header(session, "X-Cashier-Device-Code"), q.get("device_code"));
        String epochStr = firstNonBlank(header(session, "X-Cashier-Authority-Epoch"), q.get("authority_epoch"));
        String leaseToken = firstNonBlank(header(session, "X-Cashier-Lease-Token"), q.get("lease_token"));
        if (cashierKdsLeaseService != null && shopId != null && shopId > 0
                && StringUtils.hasText(device) && StringUtils.hasText(epochStr) && StringUtils.hasText(leaseToken)) {
            try {
                long epoch = Long.parseLong(epochStr.trim());
                cashierKdsLeaseService.validate(shopId, device.trim(), epoch, leaseToken.trim());
                return 1;
            } catch (Exception e) {
                log.debug("[ws/v1/notify] Cashier lease validation failed: {}", e.getMessage());
            }
        }
        return null;
    }

    private String authenticateMiniProgramToken(String rawToken) {
        if (!StringUtils.hasText(rawToken) || jwtTokenService == null) {
            return null;
        }
        String token = rawToken.trim();
        if (token.startsWith("Bearer ")) {
            token = token.substring(7).trim();
        }
        try {
            Claims claims = jwtTokenService.parseToken(token);
            if (claims != null && "user".equals(claims.getSubject()) && StringUtils.hasText(claims.getId())) {
                return claims.getId().trim();
            }
        } catch (Exception e) {
            log.debug("[ws/v1/notify] mini program user token validation failed: {}", e.getMessage());
        }
        return null;
    }

    private static Map<String, String> parseQuery(URI uri) {
        Map<String, String> values = new HashMap<>();
        if (uri == null || uri.getQuery() == null) {
            return values;
        }
        for (String item : uri.getQuery().split("&")) {
            int i = item.indexOf('=');
            if (i > 0) {
                try {
                    values.put(
                            URLDecoder.decode(item.substring(0, i), "UTF-8"),
                            URLDecoder.decode(item.substring(i + 1), "UTF-8"));
                } catch (Exception ignored) {
                }
            }
        }
        return values;
    }

    private static String header(WebSocketSession session, String name) {
        if (session == null || session.getHandshakeHeaders() == null) {
            return null;
        }
        String val = session.getHandshakeHeaders().getFirst(name);
        return StringUtils.hasText(val) ? val.trim() : null;
    }

    private static String firstNonBlank(String... candidates) {
        if (candidates == null) {
            return null;
        }
        for (String c : candidates) {
            if (StringUtils.hasText(c)) {
                return c.trim();
            }
        }
        return null;
    }

    private static String asString(Object o) {
        return o != null ? o.toString().trim() : null;
    }

    private static Integer parseIntOrNull(String s) {
        if (!StringUtils.hasText(s)) {
            return null;
        }
        try {
            return Integer.parseInt(s.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static Long parseLongOrNull(Object o) {
        if (o instanceof Number) {
            return ((Number) o).longValue();
        }
        if (o != null && StringUtils.hasText(o.toString())) {
            try {
                return Long.parseLong(o.toString().trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }
}
