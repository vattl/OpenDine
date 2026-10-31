package com.lanf.kds.service;

import com.lanf.kds.entity.KdsDevice;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Date;
import java.util.List;
import java.util.Map;

/** Cloud-owned, one-time authorization for rotating a pre-bound KDS credential. */
@Service
public class KdsPairingTicketService {

    private static final char[] CODE_ALPHABET =
            "23456789ABCDEFGHJKMNPQRSTUVWXYZ".toCharArray();
    private static final SecureRandom RANDOM = new SecureRandom();
    private final JdbcTemplate jdbc;
    private final KdsDeviceService deviceService;
    private final int ttlSeconds;

    @Autowired
    public KdsPairingTicketService(
            JdbcTemplate jdbc,
            KdsDeviceService deviceService,
            @Value("${kds.pairing-ticket-ttl-seconds:300}") int ttlSeconds) {
        this.jdbc = jdbc;
        this.deviceService = deviceService;
        this.ttlSeconds = Math.max(60, Math.min(ttlSeconds, 900));
    }

    public PairingTicket issue(int shopId, String deviceCode, String createdBy) {
        String normalizedDeviceCode = requireText(deviceCode, "device_code 不能为空");
        KdsDevice device = deviceService.findByDeviceCode(normalizedDeviceCode);
        if (device == null || !Integer.valueOf(shopId).equals(device.getShop_id())
                || !Integer.valueOf(1).equals(device.getEnabled())) {
            throw new IllegalArgumentException("KDS 设备未绑定当前门店或已禁用");
        }
        Date expiresAt = new Date(System.currentTimeMillis() + ttlSeconds * 1000L);
        String issuer = createdBy == null ? null : createdBy.trim();
        for (int attempt = 0; attempt < 3; attempt++) {
            String code = newCode();
            try {
                jdbc.update("INSERT INTO t_kds_device_pairing_ticket "
                                + "(shop_id,device_code,code_hash,expires_at,created_by) VALUES (?,?,?,?,?)",
                        shopId, normalizedDeviceCode, hashCode(code), expiresAt, issuer);
                return new PairingTicket(normalizedDeviceCode, code, expiresAt.getTime());
            } catch (DataIntegrityViolationException collision) {
                // Cryptographically improbable, but retry without ever exposing a colliding code.
            }
        }
        throw new IllegalStateException("无法生成唯一设备配对码");
    }

    @Transactional
    public KdsDevice consumeAndLogin(String pairingCode, String deviceCode,
                                     String deviceName, String screenTag,
                                     List<String> screenTags) {
        String normalizedCode = requireText(pairingCode, "pairing_code 不能为空")
                .replace("-", "").toUpperCase();
        String normalizedDeviceCode = requireText(deviceCode, "device_code 不能为空");
        List<Map<String, Object>> tickets = jdbc.queryForList(
                "SELECT id,shop_id,device_code FROM t_kds_device_pairing_ticket "
                        + "WHERE code_hash=? AND consumed_at IS NULL AND expires_at>NOW() "
                        + "LIMIT 1 FOR UPDATE",
                hashCode(normalizedCode));
        if (tickets.size() != 1) {
            throw new IllegalArgumentException("配对码无效、已使用或已过期");
        }
        Map<String, Object> ticket = tickets.get(0);
        String ticketDeviceCode = String.valueOf(ticket.get("device_code"));
        if (!normalizedDeviceCode.equals(ticketDeviceCode)) {
            throw new IllegalArgumentException("配对码与设备不匹配");
        }
        int shopId = ((Number) ticket.get("shop_id")).intValue();
        long ticketId = ((Number) ticket.get("id")).longValue();
        int consumed = jdbc.update(
                "UPDATE t_kds_device_pairing_ticket SET consumed_at=NOW() "
                        + "WHERE id=? AND consumed_at IS NULL AND expires_at>NOW()",
                ticketId);
        if (consumed != 1) {
            throw new IllegalArgumentException("配对码无效、已使用或已过期");
        }
        KdsDevice device = deviceService.loginBoundDevice(
                shopId, normalizedDeviceCode, deviceName, screenTag, screenTags, null);
        if (device == null) {
            throw new IllegalArgumentException("KDS 设备未绑定当前门店或已禁用");
        }
        return device;
    }

    static String hashCode(String code) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(code.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(digest.length * 2);
            for (byte value : digest) {
                out.append(String.format("%02x", value & 255));
            }
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static String newCode() {
        StringBuilder code = new StringBuilder(8);
        for (int i = 0; i < 8; i++) {
            code.append(CODE_ALPHABET[RANDOM.nextInt(CODE_ALPHABET.length)]);
        }
        return code.toString();
    }

    private static String requireText(String value, String message) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException(message);
        }
        return value.trim();
    }

    public static final class PairingTicket {
        private final String deviceCode;
        private final String pairingCode;
        private final long expiresAtMs;

        public PairingTicket(String deviceCode, String pairingCode, long expiresAtMs) {
            this.deviceCode = deviceCode;
            this.pairingCode = pairingCode;
            this.expiresAtMs = expiresAtMs;
        }

        public String getDeviceCode() {
            return deviceCode;
        }

        public String getPairingCode() {
            return pairingCode;
        }

        public long getExpiresAtMs() {
            return expiresAtMs;
        }
    }
}
