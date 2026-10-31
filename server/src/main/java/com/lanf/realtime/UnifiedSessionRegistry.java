package com.lanf.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 统一实时消息会话注册表（按门店、终端类型、用户OpenID多维索引）。
 * 底层复用 {@link WebSocketOutboundDispatcher} 提供单连接串行有界队列与慢消费断连保护。
 */
@Component
public class UnifiedSessionRegistry {

    private static final Logger log = LoggerFactory.getLogger(UnifiedSessionRegistry.class);

    public static final String CLIENT_TYPE_CASHIER = "CASHIER";
    public static final String CLIENT_TYPE_MINI_PROGRAM = "MINI_PROGRAM";
    public static final String CLIENT_TYPE_ALL = "ALL";

    public static final String ATTR_CLIENT_TYPE = "unified_client_type";
    public static final String ATTR_SHOP_ID = "unified_shop_id";
    public static final String ATTR_OPENID = "unified_openid";
    public static final String ATTR_USER_ID = "unified_user_id";
    public static final String ATTR_ADMIN_ID = "unified_admin_id";
    public static final String ATTR_DEVICE_ID = "unified_device_id";

    private final WebSocketOutboundDispatcher outbound;
    private final ObjectMapper objectMapper = new ObjectMapper();

    /** 全部活跃会话 */
    private final Set<WebSocketSession> allSessions = ConcurrentHashMap.newKeySet();
    /** 门店收银端会话：shopId -> Set<WebSocketSession> */
    private final ConcurrentHashMap<Integer, Set<WebSocketSession>> cashierShopSessions = new ConcurrentHashMap<>();
    /** 门店小程序会话：shopId -> Set<WebSocketSession> */
    private final ConcurrentHashMap<Integer, Set<WebSocketSession>> miniProgramShopSessions = new ConcurrentHashMap<>();
    /** 用户OpenID会话：openid -> Set<WebSocketSession> */
    private final ConcurrentHashMap<String, Set<WebSocketSession>> openidSessions = new ConcurrentHashMap<>();
    /** 用户ID会话：userId -> Set<WebSocketSession> */
    private final ConcurrentHashMap<Integer, Set<WebSocketSession>> userIdSessions = new ConcurrentHashMap<>();

    public UnifiedSessionRegistry(WebSocketOutboundDispatcher outbound) {
        this.outbound = outbound;
    }

    public void register(WebSocketSession session, String clientType, Integer shopId,
                         String openid, Integer userId, Integer adminId, String deviceId) {
        if (session == null) {
            return;
        }
        String normalizedClient = normalizeClientType(clientType);
        session.getAttributes().put(ATTR_CLIENT_TYPE, normalizedClient);
        if (shopId != null && shopId > 0) {
            session.getAttributes().put(ATTR_SHOP_ID, shopId);
        }
        if (StringUtils.hasText(openid)) {
            session.getAttributes().put(ATTR_OPENID, openid.trim());
        }
        if (userId != null && userId > 0) {
            session.getAttributes().put(ATTR_USER_ID, userId);
        }
        if (adminId != null && adminId > 0) {
            session.getAttributes().put(ATTR_ADMIN_ID, adminId);
        }
        if (StringUtils.hasText(deviceId)) {
            session.getAttributes().put(ATTR_DEVICE_ID, deviceId.trim());
        }

        allSessions.add(session);
        outbound.register(session);
        bindIndices(session, normalizedClient, shopId, openid, userId);
    }

    public void rebindContext(WebSocketSession session, Integer newShopId, String newOpenid, Integer newUserId) {
        if (session == null) {
            return;
        }
        String clientType = (String) session.getAttributes().getOrDefault(ATTR_CLIENT_TYPE, CLIENT_TYPE_MINI_PROGRAM);
        Integer oldShopId = (Integer) session.getAttributes().get(ATTR_SHOP_ID);
        String oldOpenid = (String) session.getAttributes().get(ATTR_OPENID);
        Integer oldUserId = (Integer) session.getAttributes().get(ATTR_USER_ID);

        unbindIndices(session, clientType, oldShopId, oldOpenid, oldUserId);

        Integer effectiveShopId = newShopId != null ? newShopId : oldShopId;
        String effectiveOpenid = StringUtils.hasText(newOpenid) ? newOpenid.trim() : oldOpenid;
        Integer effectiveUserId = newUserId != null ? newUserId : oldUserId;

        if (effectiveShopId != null && effectiveShopId > 0) {
            session.getAttributes().put(ATTR_SHOP_ID, effectiveShopId);
        }
        if (StringUtils.hasText(effectiveOpenid)) {
            session.getAttributes().put(ATTR_OPENID, effectiveOpenid);
        }
        if (effectiveUserId != null && effectiveUserId > 0) {
            session.getAttributes().put(ATTR_USER_ID, effectiveUserId);
        }

        bindIndices(session, clientType, effectiveShopId, effectiveOpenid, effectiveUserId);
    }

    public void unregister(WebSocketSession session) {
        if (session == null) {
            return;
        }
        allSessions.remove(session);
        String clientType = (String) session.getAttributes().get(ATTR_CLIENT_TYPE);
        Integer shopId = (Integer) session.getAttributes().get(ATTR_SHOP_ID);
        String openid = (String) session.getAttributes().get(ATTR_OPENID);
        Integer userId = (Integer) session.getAttributes().get(ATTR_USER_ID);
        unbindIndices(session, clientType, shopId, openid, userId);
        outbound.unregister(session);
    }

    public boolean isUserOnline(String openid) {
        if (!StringUtils.hasText(openid)) {
            return false;
        }
        Set<WebSocketSession> bucket = openidSessions.get(openid.trim());
        if (bucket == null || bucket.isEmpty()) {
            return false;
        }
        for (WebSocketSession s : bucket.toArray(new WebSocketSession[0])) {
            if (s != null && s.isOpen()) {
                return true;
            } else {
                bucket.remove(s);
            }
        }
        return false;
    }

    public int sendToShop(Integer shopId, String clientType, UnifiedMessageEnvelope envelope) {
        if (envelope == null) {
            return 0;
        }
        Set<WebSocketSession> targets = new HashSet<>();
        String normClient = normalizeClientType(clientType);
        if (shopId == null || shopId <= 0) {
            // shopId == 0 or null: broadcast to all shops for matching clientType
            if (CLIENT_TYPE_CASHIER.equals(normClient) || CLIENT_TYPE_ALL.equals(normClient)) {
                cashierShopSessions.values().forEach(targets::addAll);
            }
            if (CLIENT_TYPE_MINI_PROGRAM.equals(normClient) || CLIENT_TYPE_ALL.equals(normClient)) {
                miniProgramShopSessions.values().forEach(targets::addAll);
            }
            if (CLIENT_TYPE_ALL.equals(normClient)) {
                targets.addAll(allSessions);
            }
        } else {
            if (CLIENT_TYPE_CASHIER.equals(normClient) || CLIENT_TYPE_ALL.equals(normClient)) {
                targets.addAll(cashierShopSessions.getOrDefault(shopId, Collections.emptySet()));
            }
            if (CLIENT_TYPE_MINI_PROGRAM.equals(normClient) || CLIENT_TYPE_ALL.equals(normClient)) {
                targets.addAll(miniProgramShopSessions.getOrDefault(shopId, Collections.emptySet()));
            }
        }
        return dispatchEnvelopeToSessions(targets, envelope);
    }

    public int sendToUser(String openid, Integer userId, UnifiedMessageEnvelope envelope) {
        if (envelope == null) {
            return 0;
        }
        Set<WebSocketSession> targets = new HashSet<>();
        if (StringUtils.hasText(openid)) {
            targets.addAll(openidSessions.getOrDefault(openid.trim(), Collections.emptySet()));
        }
        if (userId != null && userId > 0) {
            targets.addAll(userIdSessions.getOrDefault(userId, Collections.emptySet()));
        }
        return dispatchEnvelopeToSessions(targets, envelope);
    }

    public int broadcastAll(UnifiedMessageEnvelope envelope) {
        if (envelope == null) {
            return 0;
        }
        return dispatchEnvelopeToSessions(allSessions, envelope);
    }

    public void dispatchDirect(WebSocketSession session, UnifiedMessageEnvelope envelope) {
        if (session == null || envelope == null || !session.isOpen()) {
            return;
        }
        try {
            String json = objectMapper.writeValueAsString(envelope);
            outbound.dispatch(session, new TextMessage(json));
        } catch (Exception e) {
            log.warn("[ws/v1/notify] direct dispatch failed session={}: {}", session.getId(), e.getMessage());
        }
    }

    public void acknowledgeSession(WebSocketSession session, long seqId) {
        if (session != null && seqId > 0) {
            outbound.acknowledge(session, String.valueOf(seqId));
        }
    }

    public void acknowledgeSessionMessage(WebSocketSession session, String messageId) {
        if (session != null && StringUtils.hasText(messageId)) {
            outbound.acknowledge(session, messageId.trim());
        }
    }

    private int dispatchEnvelopeToSessions(Set<WebSocketSession> sessions, UnifiedMessageEnvelope envelope) {
        if (sessions == null || sessions.isEmpty()) {
            return 0;
        }
        final String json;
        try {
            json = objectMapper.writeValueAsString(envelope);
        } catch (Exception e) {
            log.warn("[ws/v1/notify] serialize envelope failed event={}: {}", envelope.getEvent_type(), e.getMessage());
            return 0;
        }
        TextMessage message = new TextMessage(json);
        int sent = 0;
        for (WebSocketSession session : sessions.toArray(new WebSocketSession[0])) {
            if (session == null || !session.isOpen()) {
                unregister(session);
                continue;
            }
            try {
                boolean accepted = outbound.dispatch(session, message);
                if (accepted) {
                    sent++;
                }
            } catch (Exception e) {
                unregister(session);
                log.warn("[ws/v1/notify] dispatch failed session={}: {}", session.getId(), e.getMessage());
            }
        }
        return sent;
    }

    private void bindIndices(WebSocketSession session, String clientType, Integer shopId, String openid, Integer userId) {
        if (shopId != null && shopId > 0) {
            if (CLIENT_TYPE_CASHIER.equals(clientType)) {
                cashierShopSessions.computeIfAbsent(shopId, k -> ConcurrentHashMap.newKeySet()).add(session);
            } else {
                miniProgramShopSessions.computeIfAbsent(shopId, k -> ConcurrentHashMap.newKeySet()).add(session);
            }
        }
        if (StringUtils.hasText(openid)) {
            openidSessions.computeIfAbsent(openid.trim(), k -> ConcurrentHashMap.newKeySet()).add(session);
        }
        if (userId != null && userId > 0) {
            userIdSessions.computeIfAbsent(userId, k -> ConcurrentHashMap.newKeySet()).add(session);
        }
    }

    private void unbindIndices(WebSocketSession session, String clientType, Integer shopId, String openid, Integer userId) {
        if (shopId != null && shopId > 0) {
            Set<WebSocketSession> cSet = cashierShopSessions.get(shopId);
            if (cSet != null) {
                cSet.remove(session);
            }
            Set<WebSocketSession> mSet = miniProgramShopSessions.get(shopId);
            if (mSet != null) {
                mSet.remove(session);
            }
        }
        if (StringUtils.hasText(openid)) {
            Set<WebSocketSession> oSet = openidSessions.get(openid.trim());
            if (oSet != null) {
                oSet.remove(session);
            }
        }
        if (userId != null && userId > 0) {
            Set<WebSocketSession> uSet = userIdSessions.get(userId);
            if (uSet != null) {
                uSet.remove(session);
            }
        }
    }

    public static String normalizeClientType(String raw) {
        if (!StringUtils.hasText(raw)) {
            return CLIENT_TYPE_MINI_PROGRAM;
        }
        String upper = raw.trim().toUpperCase();
        if ("CASHIER".equals(upper) || "POS".equals(upper) || "ADMIN".equals(upper)) {
            return CLIENT_TYPE_CASHIER;
        }
        if ("ALL".equals(upper)) {
            return CLIENT_TYPE_ALL;
        }
        return CLIENT_TYPE_MINI_PROGRAM;
    }

    public java.util.Map<String, Object> getShopSessionStats(Integer shopId) {
        int targetShop = shopId != null && shopId > 0 ? shopId : 1;
        Set<WebSocketSession> cSessions = cashierShopSessions.get(targetShop);
        int cashierCount = 0;
        if (cSessions != null) {
            for (WebSocketSession s : cSessions) {
                if (s != null && s.isOpen()) {
                    cashierCount++;
                }
            }
        }
        Set<WebSocketSession> mSessions = miniProgramShopSessions.get(targetShop);
        int miniCount = 0;
        if (mSessions != null) {
            for (WebSocketSession s : mSessions) {
                if (s != null && s.isOpen()) {
                    miniCount++;
                }
            }
        }
        java.util.Map<String, Object> stats = new java.util.LinkedHashMap<>();
        stats.put("shop_id", targetShop);
        stats.put("cashier_online_count", cashierCount);
        stats.put("mini_program_online_count", miniCount);
        stats.put("total_connected_sessions", allSessions.size());
        return stats;
    }
}
