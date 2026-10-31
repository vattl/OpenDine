package com.lanf.kds.delivery;

import com.lanf.kds.service.KdsCashierAuthorityService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.util.*;

@Service
public class CashierKdsLeaseService {
    public static final long LEASE_MS = 30_000L;
    private final JdbcTemplate jdbc;
    private final KdsCashierAuthorityService authorityService;
    private final SecureRandom random = new SecureRandom();

    public CashierKdsLeaseService(JdbcTemplate jdbc, KdsCashierAuthorityService authorityService) {
        this.jdbc = jdbc;
        this.authorityService = authorityService;
    }

    @Transactional
    public Map<String, Object> lease(int shopId, String deviceCode, Map<String, Object> body) {
        String device = KdsCashierAuthorityService.normalize(deviceCode);
        authorityService.requirePrimaryPublisher(shopId, device);
        jdbc.update("INSERT IGNORE INTO t_kds_delivery_consumer (shop_id) VALUES (?)", shopId);
        LeaseContext current = loadForUpdate(shopId);
        String action = text(body == null ? null : body.get("action")).toUpperCase(Locale.ROOT);
        long now = System.currentTimeMillis();
        String token;
        long epoch;
        if ("RENEW".equals(action)) {
            epoch = number(body.get("authorityEpoch"));
            token = text(body.get("leaseToken"));
            requireToken(current, device, epoch, token, now);
        } else if ("ACQUIRE".equals(action)) {
            if (current.leaseUntilMs > now && current.deviceCode != null) {
                throw conflict("本门店已有有效的主收银 KDS 会话，请等待租约到期或由原会话续租");
            }
            epoch = current.epoch + 1;
            token = newToken();
            long head = head(shopId);
            jdbc.update("UPDATE t_kds_delivery_consumer SET device_code=?,authority_epoch=?,lease_token_hash=?,"
                            + "lease_until=?,bootstrap_base_cursor=?,bootstrap_required=1,client_version=?,last_seen_at=NOW() WHERE shop_id=?",
                    device, epoch, sha256(token), new Timestamp(now + LEASE_MS), head,
                    trim(text(body == null ? null : body.get("clientVersion")), 64), shopId);
            current = loadForUpdate(shopId);
        } else {
            throw new CashierKdsDeliveryException(400, 4000, "action must be ACQUIRE or RENEW");
        }
        long until = now + LEASE_MS;
        jdbc.update("UPDATE t_kds_delivery_consumer SET lease_until=?,last_seen_at=NOW(),client_version=COALESCE(?,client_version) WHERE shop_id=?",
                new Timestamp(until), trim(text(body == null ? null : body.get("clientVersion")), 64), shopId);
        LeaseContext latest = loadForUpdate(shopId);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("shopId", shopId); data.put("deviceCode", device); data.put("authorityEpoch", epoch);
        data.put("leaseToken", token); data.put("leaseUntilMs", until); data.put("renewAfterMs", 10_000L);
        data.put("snapshotRequired", latest.bootstrapRequired); data.put("lastAckCursor", latest.ackCursor);
        data.put("headCursor", head(shopId));
        return data;
    }

    public LeaseContext validate(int shopId, String deviceCode, long epoch, String token) {
        LeaseContext context = load(shopId);
        requireToken(context, KdsCashierAuthorityService.normalize(deviceCode), epoch, token, System.currentTimeMillis());
        return context;
    }

    @Transactional
    public LeaseContext validateForUpdate(int shopId, String deviceCode, long epoch, String token) {
        LeaseContext context = loadForUpdate(shopId);
        requireToken(context, KdsCashierAuthorityService.normalize(deviceCode), epoch, token, System.currentTimeMillis());
        return context;
    }

    /** Short fenced commit after page reading; pagination must not monopolize the lease row. */
    @Transactional
    public void recordBootstrapPage(int shop, String device, long epoch, String token, long base, boolean complete) {
        validateForUpdate(shop,device,epoch,token);
        if (complete) {
            jdbc.update("UPDATE t_kds_delivery_consumer SET bootstrap_base_cursor=?,last_delivered_cursor=GREATEST(last_delivered_cursor,?),last_seen_at=NOW() WHERE shop_id=?",
                    base,base,shop);
        } else {
            // A partial page must not allow ACK to clear the bootstrap gate.
            jdbc.update("UPDATE t_kds_delivery_consumer SET bootstrap_base_cursor=?,bootstrap_required=1,last_seen_at=NOW() WHERE shop_id=?",
                    Long.MAX_VALUE,shop);
        }
    }
    public long head(int shopId) {
        Long value = jdbc.queryForObject("SELECT COALESCE(MAX(id),0) FROM t_kds_delivery_event WHERE shop_id=?", Long.class, shopId);
        return value == null ? 0 : value;
    }

    private LeaseContext load(int shopId) {
        List<LeaseContext> rows = jdbc.query("SELECT * FROM t_kds_delivery_consumer WHERE shop_id=?", this::map, shopId);
        if (rows.isEmpty()) throw conflict("主收银 KDS 租约不存在，请先 ACQUIRE");
        return rows.get(0);
    }
    private LeaseContext loadForUpdate(int shopId) {
        List<LeaseContext> rows = jdbc.query("SELECT * FROM t_kds_delivery_consumer WHERE shop_id=? FOR UPDATE", this::map, shopId);
        if (rows.isEmpty()) throw conflict("主收银 KDS 租约不存在，请先 ACQUIRE");
        return rows.get(0);
    }
    private LeaseContext map(java.sql.ResultSet rs, int rowNum) throws java.sql.SQLException {
        LeaseContext c = new LeaseContext();
        c.shopId = rs.getInt("shop_id"); c.deviceCode = rs.getString("device_code");
        c.epoch = rs.getLong("authority_epoch"); c.tokenHash = rs.getString("lease_token_hash");
        Timestamp until = rs.getTimestamp("lease_until"); c.leaseUntilMs = until == null ? 0 : until.getTime();
        c.ackCursor = rs.getLong("ack_cursor"); c.lastDeliveredCursor = rs.getLong("last_delivered_cursor");
        c.bootstrapBaseCursor = rs.getLong("bootstrap_base_cursor"); c.bootstrapRequired = rs.getBoolean("bootstrap_required");
        return c;
    }
    private static void requireToken(LeaseContext c, String device, long epoch, String token, long now) {
        if (!device.equals(c.deviceCode) || epoch != c.epoch || !constantEquals(c.tokenHash, sha256(token))) {
            throw conflict("主收银 KDS 租约凭证已失效，请重新获取租约");
        }
        if (c.leaseUntilMs <= now) throw conflict("主收银 KDS 租约已过期，请重新 ACQUIRE");
    }
    private String newToken() {
        byte[] bytes = new byte[32]; random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
    static CashierKdsDeliveryException conflict(String message) {
        return new CashierKdsDeliveryException(409, 4090, message);
    }
    static String sha256(String value) {
        if (value == null) return "";
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) out.append(String.format("%02x", b & 0xff));
            return out.toString();
        } catch (Exception ex) { throw new IllegalStateException(ex); }
    }
    private static boolean constantEquals(String left, String right) {
        return left != null && MessageDigest.isEqual(left.getBytes(StandardCharsets.US_ASCII), right.getBytes(StandardCharsets.US_ASCII));
    }
    private static String text(Object value) { return value == null ? "" : String.valueOf(value).trim(); }
    private static long number(Object value) {
        if (value instanceof Number) return ((Number) value).longValue();
        try { return Long.parseLong(text(value)); }
        catch (Exception ex) { throw new CashierKdsDeliveryException(400, 4000, "authorityEpoch is required"); }
    }
    private static String trim(String value, int max) { return value.isEmpty() ? null : value.substring(0, Math.min(max, value.length())); }

    public static final class LeaseContext {
        public int shopId; public String deviceCode; public long epoch; String tokenHash;
        public long leaseUntilMs; public long ackCursor; public long lastDeliveredCursor;
        public long bootstrapBaseCursor; public boolean bootstrapRequired;
    }
}
