package com.lanf.kds.service;

import com.lanf.kds.replication.KdsReplicationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.List;

/** Shop-scoped cashier authority identity. It is intentionally unrelated to KDS display devices. */
@Service
public class KdsCashierAuthorityService {
    private final JdbcTemplate jdbc;

    public KdsCashierAuthorityService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    public void configure(int shopId, String cashierDeviceCode) {
        String normalized = normalize(cashierDeviceCode);
        jdbc.update("INSERT IGNORE INTO t_kds_authority_config_version (shop_id,version) VALUES (?,1)", shopId);
        List<String> current = jdbc.queryForList("SELECT cashier_device_code FROM t_kds_authority_config_version "
                + "WHERE shop_id=? FOR UPDATE", String.class, shopId);
        if (!current.isEmpty() && normalized.equals(current.get(0))) return;
        jdbc.update("UPDATE t_kds_authority_config_version SET version=version+1,cashier_device_code=?,"
                + "snapshot_hash=NULL,updated_at=NOW() WHERE shop_id=?", normalized, shopId);
    }

    /** Must be invoked inside the state-application transaction; FOR UPDATE fences concurrent reconfiguration. */
    public void requirePrimaryPublisher(int shopId, String cashierDeviceCode) {
        requireConfiguredPublisher(shopId, cashierDeviceCode, true);
    }

    /** Read-only identity check for proxy requests that do not mutate authoritative business state. */
    public void requireConfiguredPublisher(int shopId, String cashierDeviceCode) {
        requireConfiguredPublisher(shopId, cashierDeviceCode, false);
    }

    private void requireConfiguredPublisher(int shopId, String cashierDeviceCode, boolean lockForUpdate) {
        String normalized = normalize(cashierDeviceCode);
        List<String> configured = jdbc.queryForList("SELECT cashier_device_code FROM t_kds_authority_config_version "
                + "WHERE shop_id=?" + (lockForUpdate ? " FOR UPDATE" : ""), String.class, shopId);
        if (configured.isEmpty() || !StringUtils.hasText(configured.get(0))) {
            throw new KdsReplicationException("cashier authority is not configured for this shop");
        }
        if (!normalized.equals(configured.get(0))) {
            throw new KdsReplicationException("device_code is not the configured cashier authority");
        }
    }

    public static String normalize(String deviceCode) {
        if (!StringUtils.hasText(deviceCode) || deviceCode.trim().length() > 64) {
            throw new IllegalArgumentException("cashier_device_code is required and must not exceed 64 characters");
        }
        return deviceCode.trim();
    }
}
