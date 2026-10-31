package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.mapper.AdminPushDeviceMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** Stores mobile push tokens and per-shop notification preferences. */
@Service
public class AdminPushDeviceService {

    @Autowired
    private AdminPushDeviceMapper deviceMapper;
    @Autowired
    private JdbcTemplate jdbcTemplate;
    @Autowired
    private ObjectMapper objectMapper;

    @Transactional(rollbackFor = Exception.class)
    public void register(Integer adminId, Integer shopId, String token, String platform,
                         String channel, String appVersion, String deviceModel) {
        if (deviceMapper.register(adminId, shopId, token, platform, channel,
                appVersion, deviceModel) < 1) {
            throw new IllegalStateException("推送设备注册失败");
        }
    }

    @Transactional(rollbackFor = Exception.class)
    public void unregister(Integer adminId, String token) {
        deviceMapper.unregister(adminId, token);
    }

    @Transactional(rollbackFor = Exception.class)
    public void savePreference(Integer adminId, Integer shopId, List<String> types) {
        try {
            String json = objectMapper.writeValueAsString(types);
            jdbcTemplate.update(
                    "INSERT INTO t_admin_push_preference(admin_id,shop_id,types_json) VALUES(?,?,?) "
                            + "ON DUPLICATE KEY UPDATE types_json=VALUES(types_json),updated_at=NOW()",
                    adminId, shopId, json);
        } catch (Exception e) {
            throw new IllegalStateException("通知偏好保存失败", e);
        }
    }
}
