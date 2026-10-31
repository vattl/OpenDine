package com.lanf.kds.service;

import com.lanf.kds.KdsScreenTag;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * KDS 设备可见烤制岗存储（t_kds_device_screen）。
 * 无记录 = 默认三岗全选（见 {@link KdsDeviceService#screenTagsOf}）。
 */
@Repository
@org.springframework.context.annotation.DependsOn("paymentSchemaReadiness")
public class KdsDeviceScreenStore {

    private final JdbcTemplate jdbc;

    public KdsDeviceScreenStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<String> get(long deviceId) {
        List<String> rows = jdbc.queryForList(
                "SELECT screen_tags FROM t_kds_device_screen WHERE device_id=?", String.class, deviceId);
        if (rows.isEmpty()) {
            return Collections.emptyList();
        }
        return normalizeList(Arrays.asList(rows.get(0).split(",")));
    }

    public void save(long deviceId, List<String> screenTags) {
        List<String> normalized = normalizeList(screenTags);
        if (normalized.isEmpty()) {
            delete(deviceId);
            return;
        }
        jdbc.update("INSERT INTO t_kds_device_screen(device_id, screen_tags) VALUES (?,?) "
                + "ON DUPLICATE KEY UPDATE screen_tags=VALUES(screen_tags)",
                deviceId, String.join(",", normalized));
    }

    public void delete(long deviceId) {
        jdbc.update("DELETE FROM t_kds_device_screen WHERE device_id=?", deviceId);
    }

    /** 仅保留烤制三岗，去重保序；全非法/空 → 空列表（调用方回默认三岗）。 */
    static List<String> normalizeList(List<String> raw) {
        if (raw == null || raw.isEmpty()) {
            return Collections.emptyList();
        }
        Set<String> allowed = new LinkedHashSet<>(KdsScreenTag.PRODUCTION_GRILL_TAGS);
        List<String> out = new ArrayList<>();
        for (String s : raw) {
            if (s == null) {
                continue;
            }
            String tag = s.trim();
            if (allowed.contains(tag) && !out.contains(tag)) {
                out.add(tag);
            }
        }
        return out;
    }
}
