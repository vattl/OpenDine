package com.lanf.kds;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Opt-in HTTP drill for a disposable clone of the populated debug database.
 * The runner must point Spring at a randomly named *_cursor_drill_* database;
 * this test refuses to prune the source debug database.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("debug")
@EnabledIfEnvironmentVariable(named = "RUN_REAL_KDS_CURSOR_EXPIRY", matches = "(?i)true")
class KdsRealSnapshotCursorExpiryDrillTest {

    private static final int SHOP_ID = 1;

    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private TestRestTemplate http;
    @Value("${spring.datasource.url}")
    private String dataSourceUrl;

    @Test
    void expiredRealCursorRequiresAndRecoversThroughBootstrap() throws Exception {
        assertTrue(dataSourceUrl.matches(".*[/]db_diancan_kds_cursor_drill_[a-z0-9]+(?:[?].*)?$"),
                "cursor 裁剪只能运行在随机命名的独立 debug 快照库");

        Map<String, Object> device = jdbc.queryForMap(
                "SELECT id,device_code FROM t_kds_device WHERE shop_id=? "
                        + "AND screen_tag IS NOT NULL ORDER BY id LIMIT 1", SHOP_ID);
        List<Long> retainedSequences = jdbc.queryForList(
                "SELECT event_seq FROM t_kds_v2_event WHERE shop_id=? "
                        + "ORDER BY event_seq ASC LIMIT 6", Long.class, SHOP_ID);
        assertTrue(retainedSequences.size() >= 6,
                "独立快照至少需要 6 个真实保留事件构造过期窗口");

        long currentCursor = requiredLong(jdbc.queryForObject(
                "SELECT event_seq FROM t_kds_v2_event_cursor WHERE shop_id=?",
                Long.class, SHOP_ID));
        int ticketCount = count("SELECT COUNT(*) FROM t_kds_ticket");
        int commandCount = count("SELECT COUNT(*) FROM t_kds_v2_command");
        String token = UUID.randomUUID().toString().replace("-", "")
                + UUID.randomUUID().toString().replace("-", "");
        long deviceId = ((Number) device.get("id")).longValue();

        jdbc.update("UPDATE t_kds_device SET device_token=NULL,token_hash=?,"
                        + "token_expires_at=DATE_ADD(NOW(),INTERVAL 1 HOUR),token_revoked_at=NULL,"
                        + "last_heartbeat_at=NOW(),enabled=1,updated_at=NOW() WHERE id=?",
                sha256(token), deviceId);
        long pruneThrough = retainedSequences.get(4);
        int deleted = jdbc.update(
                "DELETE FROM t_kds_v2_event WHERE shop_id=? AND event_seq<=?",
                SHOP_ID, pruneThrough);
        assertTrue(deleted >= 5);
        long retainedMinimum = requiredLong(jdbc.queryForObject(
                "SELECT MIN(event_seq) FROM t_kds_v2_event WHERE shop_id=?",
                Long.class, SHOP_ID));
        assertTrue(retainedMinimum > 1L);

        HttpHeaders headers = new HttpHeaders();
        headers.set("X-Kds-Device-Token", token);
        HttpEntity<Void> request = new HttpEntity<>(headers);

        Map<String, Object> changes = body(http.exchange(
                "/kds/v2/changes?after_seq=0", HttpMethod.GET, request, Map.class));
        assertEquals(0, ((Number) changes.get("code")).intValue());
        assertEquals(Boolean.TRUE, changes.get("snapshot_required"));
        assertEquals(currentCursor, ((Number) changes.get("event_seq")).longValue());
        assertTrue(((List<?>) changes.get("events")).isEmpty());

        Map<String, Object> bootstrap = body(http.exchange(
                "/kds/v2/bootstrap", HttpMethod.GET, request, Map.class));
        assertEquals(0, ((Number) bootstrap.get("code")).intValue());
        assertEquals(2, ((Number) bootstrap.get("protocol_version")).intValue());
        assertEquals(currentCursor, ((Number) bootstrap.get("event_seq")).longValue());
        assertNotNull(bootstrap.get("queues"));
        assertNotNull(bootstrap.get("order_details"));

        Map<String, Object> resumed = body(http.exchange(
                "/kds/v2/changes?after_seq=" + currentCursor,
                HttpMethod.GET, request, Map.class));
        assertEquals(Boolean.FALSE, resumed.get("snapshot_required"));
        assertEquals(currentCursor, ((Number) resumed.get("event_seq")).longValue());
        assertTrue(((List<?>) resumed.get("events")).isEmpty());

        assertEquals(ticketCount, count("SELECT COUNT(*) FROM t_kds_ticket"));
        assertEquals(commandCount, count("SELECT COUNT(*) FROM t_kds_v2_command"));
        assertEquals(currentCursor, requiredLong(jdbc.queryForObject(
                "SELECT event_seq FROM t_kds_v2_event_cursor WHERE shop_id=?",
                Long.class, SHOP_ID)));
        assertFalse(String.valueOf(device.get("device_code")).trim().isEmpty());
    }

    private int count(String sql) {
        Integer value = jdbc.queryForObject(sql, Integer.class);
        return value == null ? 0 : value;
    }

    private static long requiredLong(Long value) {
        assertNotNull(value);
        return value;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> response) {
        assertTrue(response.getStatusCode().is2xxSuccessful());
        assertNotNull(response.getBody());
        return (Map<String, Object>) response.getBody();
    }

    private static String sha256(String value) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder out = new StringBuilder(digest.length * 2);
        for (byte item : digest) out.append(String.format("%02x", item & 0xff));
        return out.toString();
    }
}
