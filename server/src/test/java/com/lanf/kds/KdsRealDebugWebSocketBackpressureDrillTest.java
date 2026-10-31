package com.lanf.kds;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.realtime.KdsWebSocketHub;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import javax.websocket.ContainerProvider;
import javax.websocket.WebSocketContainer;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Timestamp;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Opt-in real-network drill using retained event envelopes from the populated debug database.
 * No order, ticket, command or event row is created. The selected device credential is restored
 * field-for-field in finally.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("debug")
@EnabledIfEnvironmentVariable(named = "RUN_REAL_KDS_WS_BACKPRESSURE", matches = "(?i)true")
class KdsRealDebugWebSocketBackpressureDrillTest {

    private static final int SHOP_ID = 1;

    @LocalServerPort
    private int port;
    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private KdsWebSocketHub hub;
    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void realRetainedEventsCloseOnlyTheUnacknowledgedConsumer() throws Exception {
        Map<String, Object> device = jdbc.queryForMap(
                "SELECT id,shop_id,screen_tag,device_code,device_token,token_hash,"
                        + "token_expires_at,token_revoked_at,last_heartbeat_at,enabled,updated_at "
                        + "FROM t_kds_device WHERE shop_id=? AND screen_tag IS NOT NULL "
                        + "ORDER BY id ASC LIMIT 1", SHOP_ID);
        List<String> envelopes = jdbc.query(
                "SELECT event_json FROM t_kds_v2_event WHERE shop_id=? "
                        + "AND event_json IS NOT NULL ORDER BY event_seq ASC LIMIT 34",
                (row, index) -> row.getString(1), SHOP_ID);
        assertTrue(envelopes.size() >= 34,
                "真实 debug 事件日志至少需要 34 个保留信封验证 32 帧窗口");

        String token = UUID.randomUUID().toString().replace("-", "")
                + UUID.randomUUID().toString().replace("-", "");
        long deviceId = ((Number) device.get("id")).longValue();
        int beforeTickets = ticketCount();
        int beforeCommands = commandCount();
        int beforeEvents = eventCount();
        long beforeCursor = cursor();

        WebSocketSession slow = null;
        WebSocketSession healthy = null;
        try {
            jdbc.update("UPDATE t_kds_device SET device_token=NULL,token_hash=?,"
                            + "token_expires_at=DATE_ADD(NOW(),INTERVAL 1 HOUR),token_revoked_at=NULL,"
                            + "last_heartbeat_at=NOW(),enabled=1,updated_at=NOW() WHERE id=?",
                    sha256(token), deviceId);

            ProbeHandler slowHandler = new ProbeHandler(false, objectMapper);
            ProbeHandler healthyHandler = new ProbeHandler(true, objectMapper);
            slow = connect(token, device, slowHandler);
            healthy = connect(token, device, healthyHandler);
            assertTrue(awaitHubSessions(2, 5, TimeUnit.SECONDS),
                    "服务端必须先登记两个真实 WebSocket 会话");

            int overflowIndex = -1;
            for (int index = 0; index < 33; index++) {
                int accepted = hub.broadcastV2(
                        SHOP_ID, String.valueOf(device.get("screen_tag")), envelopes.get(index));
                assertTrue(accepted >= 1,
                        "确认型真实连接必须持续接受事件，index=" + index);
                if (index == 0) {
                    assertEquals(2, accepted, "首帧必须同时进入两个真实连接");
                }
                assertTrue(healthyHandler.awaitCount(index + 1, 2, TimeUnit.SECONDS),
                        "确认型客户端必须持续收到真实事件，index=" + index
                                + ", error=" + healthyHandler.transportError.get());
                if (slowHandler.closed.await(100, TimeUnit.MILLISECONDS)) {
                    overflowIndex = index;
                    break;
                }
            }

            assertTrue(overflowIndex >= 0 || slowHandler.closed.await(5, TimeUnit.SECONDS),
                    "未确认客户端必须在窗口溢出后关闭");
            assertNotNull(slowHandler.closeStatus.get());
            assertEquals("ack window overflow", slowHandler.closeStatus.get().getReason());
            assertTrue(healthy.isOpen(), "确认型客户端不得被慢连接连带关闭");
            assertTrue(awaitHubSessions(1, 5, TimeUnit.SECONDS),
                    "慢连接关闭后只应保留确认型连接");

            int continuationIndex = overflowIndex + 1;
            assertTrue(continuationIndex < envelopes.size(), "必须保留一帧验证隔离后的持续投递");
            assertEquals(1, hub.broadcastV2(SHOP_ID,
                    String.valueOf(device.get("screen_tag")), envelopes.get(continuationIndex)));
            assertTrue(healthyHandler.awaitCount(continuationIndex + 1, 2, TimeUnit.SECONDS));
            assertTrue(healthy.isOpen());
        } finally {
            closeQuietly(slow);
            closeQuietly(healthy);
            jdbc.update("UPDATE t_kds_device SET device_token=?,token_hash=?,token_expires_at=?,"
                            + "token_revoked_at=?,last_heartbeat_at=?,enabled=?,updated_at=? WHERE id=?",
                    device.get("device_token"), device.get("token_hash"),
                    device.get("token_expires_at"), device.get("token_revoked_at"),
                    device.get("last_heartbeat_at"), device.get("enabled"),
                    device.get("updated_at"), deviceId);
        }

        assertEquals(beforeTickets, ticketCount());
        assertEquals(beforeCommands, commandCount());
        assertEquals(beforeEvents, eventCount());
        assertEquals(beforeCursor, cursor());
        Map<String, Object> restored = jdbc.queryForMap(
                "SELECT device_token,token_hash,token_expires_at,token_revoked_at,"
                        + "last_heartbeat_at,enabled,updated_at FROM t_kds_device WHERE id=?",
                deviceId);
        assertEquals(device.get("device_token"), restored.get("device_token"));
        assertEquals(device.get("token_hash"), restored.get("token_hash"));
        assertTimestampEquals(device.get("token_expires_at"), restored.get("token_expires_at"));
        assertTimestampEquals(device.get("token_revoked_at"), restored.get("token_revoked_at"));
        assertTimestampEquals(device.get("last_heartbeat_at"), restored.get("last_heartbeat_at"));
        assertEquals(device.get("enabled"), restored.get("enabled"));
        assertTimestampEquals(device.get("updated_at"), restored.get("updated_at"));
    }

    private WebSocketSession connect(String token, Map<String, Object> device,
                                     ProbeHandler handler) throws Exception {
        String screenTag = URLEncoder.encode(String.valueOf(device.get("screen_tag")), "UTF-8");
        URI uri = URI.create("ws://127.0.0.1:" + port + "/ws/kds/v2?shop_id="
                + device.get("shop_id") + "&screen_tag=" + screenTag);
        WebSocketHttpHeaders headers = new WebSocketHttpHeaders();
        headers.add("X-Kds-Device-Token", token);
        WebSocketContainer container = ContainerProvider.getWebSocketContainer();
        container.setDefaultMaxTextMessageBufferSize(65536);
        return new StandardWebSocketClient(container).doHandshake(handler, headers, uri)
                .get(10, TimeUnit.SECONDS);
    }

    private int ticketCount() {
        return count("SELECT COUNT(*) FROM t_kds_ticket");
    }

    private int commandCount() {
        return count("SELECT COUNT(*) FROM t_kds_v2_command");
    }

    private int eventCount() {
        return count("SELECT COUNT(*) FROM t_kds_v2_event");
    }

    private int count(String sql) {
        Integer value = jdbc.queryForObject(sql, Integer.class);
        return value != null ? value : 0;
    }

    private long cursor() {
        Long value = jdbc.queryForObject(
                "SELECT COALESCE(MAX(event_seq),0) FROM t_kds_v2_event_cursor", Long.class);
        return value != null ? value : 0L;
    }

    private boolean awaitHubSessions(int expected, long timeout, TimeUnit unit)
            throws InterruptedException {
        long deadline = System.nanoTime() + unit.toNanos(timeout);
        while (hub.sessionCount() != expected && System.nanoTime() < deadline) {
            Thread.sleep(5);
        }
        return hub.sessionCount() == expected;
    }

    private static String sha256(String value) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder out = new StringBuilder(digest.length * 2);
        for (byte item : digest) out.append(String.format("%02x", item & 0xff));
        return out.toString();
    }

    private static void closeQuietly(WebSocketSession session) {
        if (session == null) return;
        try {
            session.close();
        } catch (Exception ignore) {
        }
    }

    private static void assertTimestampEquals(Object expected, Object actual) {
        if (expected == null || actual == null) {
            assertEquals(expected, actual);
            return;
        }
        assertEquals(((Timestamp) expected).getTime(), ((Timestamp) actual).getTime());
    }

    private static final class ProbeHandler extends TextWebSocketHandler {
        private final boolean acknowledge;
        private final ObjectMapper objectMapper;
        private final AtomicInteger received = new AtomicInteger();
        private final CountDownLatch closed = new CountDownLatch(1);
        private final AtomicReference<CloseStatus> closeStatus = new AtomicReference<>();
        private final AtomicReference<String> transportError = new AtomicReference<>();

        private ProbeHandler(boolean acknowledge, ObjectMapper objectMapper) {
            this.acknowledge = acknowledge;
            this.objectMapper = objectMapper;
        }

        @Override
        protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
            JsonNode event = objectMapper.readTree(message.getPayload());
            if (acknowledge) {
                Map<String, Object> ack = new LinkedHashMap<>();
                ack.put("protocol_version", 2);
                ack.put("type", "ack");
                ack.put("event_seq", event.path("event_seq").asLong());
                ack.put("event_id", event.path("event_id").asText());
                session.sendMessage(new TextMessage(objectMapper.writeValueAsString(ack)));
            }
            received.incrementAndGet();
        }

        @Override
        public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
            closeStatus.set(status);
            closed.countDown();
        }

        @Override
        public void handleTransportError(WebSocketSession session, Throwable exception) {
            transportError.set(exception.getClass().getSimpleName() + ":" + exception.getMessage());
        }

        private boolean awaitCount(int expected, long timeout, TimeUnit unit) throws InterruptedException {
            long deadline = System.nanoTime() + unit.toNanos(timeout);
            while (received.get() < expected && System.nanoTime() < deadline) {
                Thread.sleep(5);
            }
            return received.get() >= expected;
        }
    }
}
