package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.event.KdsDeviceCredentialChangedEvent;
import com.lanf.kds.mapper.KdsDeviceMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.*;

@Service
public class KdsDeviceService {

    private static final SecureRandom TOKEN_RANDOM = new SecureRandom();

    @Autowired
    private KdsWorkflowStore workflowStore;
    @Autowired
    private KdsDeviceScreenStore screenStore;

    @Autowired
    private KdsDeviceMapper deviceMapper;
    @Autowired
    private KdsStationService stationService;
    @Autowired(required = false)
    private KdsConfigService configService;
    @Autowired(required = false)
    private ApplicationEventPublisher eventPublisher;
    @Autowired(required = false)
    private org.springframework.jdbc.core.JdbcTemplate jdbc;
    @Value("${kds.device-token-ttl-seconds:2592000}")
    private long deviceTokenTtlSeconds = 2592000L;

    public List<KdsDevice> listByShop(int shopId) {
        List<KdsDevice> list = deviceMapper.selectList(new QueryWrapper<KdsDevice>()
                .eq("shop_id", shopId)
                .eq("enabled", 1)
                .orderByDesc("id"));
        for (KdsDevice device : list) {
            enrichWorkflows(device);
            enrichScreens(device);
        }
        return list;
    }

    public KdsDevice findByDeviceCode(String deviceCode) {
        if (deviceCode == null || deviceCode.trim().isEmpty()) {
            return null;
        }
        return deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("device_code", deviceCode.trim())
                .last("LIMIT 1"));
    }

    public KdsDevice bind(int shopId, String deviceCode, String deviceName, String screenTag) {
        return bind(shopId, deviceCode, deviceName, screenTag, null);
    }

    public KdsDevice bind(int shopId, String deviceCode, String deviceName, String screenTag, List<String> screenTags) {
        return bind(shopId, deviceCode, deviceName, screenTag, screenTags, null);
    }

    public KdsDevice bind(int shopId, String deviceCode, String deviceName, String screenTag, List<String> screenTags, String explicitToken) {
        return bindInternal(shopId, deviceCode, deviceName, screenTag, screenTags, true, explicitToken);
    }

    /**
     * Issues a credential only for an already-bound, enabled device. The row
     * lock keeps a concurrent disable/unbind from being overwritten by the
     * token rotation performed by {@link #bindInternal}.
     */
    @Transactional
    public KdsDevice loginBoundDevice(int shopId, String deviceCode, String deviceName,
                                      String screenTag, List<String> screenTags, String explicitToken) {
        if (deviceCode == null || deviceCode.trim().isEmpty()) {
            throw new IllegalArgumentException("device_code 不能为空");
        }
        String normalizedCode = deviceCode.trim();
        KdsDevice bound = deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("device_code", normalizedCode)
                .last("LIMIT 1 FOR UPDATE"));
        if (bound == null || !Integer.valueOf(shopId).equals(bound.getShop_id())
                || !Integer.valueOf(1).equals(bound.getEnabled())) {
            return null;
        }
        return bindInternal(shopId, normalizedCode, deviceName, screenTag, screenTags, true, explicitToken);
    }

    /**
     * Authenticates and auto-binds a device when verified with the store's 6-digit PIN.
     */
    @Transactional
    public KdsDevice bindOrLoginByPin(int shopId, String deviceCode, String deviceName,
                                      String screenTag, List<String> screenTags) {
        if (deviceCode == null || deviceCode.trim().isEmpty()) {
            throw new IllegalArgumentException("device_code 不能为空");
        }
        String normalizedCode = deviceCode.trim();
        KdsDevice existing = deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("device_code", normalizedCode)
                .last("LIMIT 1 FOR UPDATE"));
        if (existing != null && !Integer.valueOf(shopId).equals(existing.getShop_id())) {
            throw new IllegalArgumentException("该设备已绑定其他门店 (门店ID: " + existing.getShop_id() + ")");
        }
        return bindInternal(shopId, normalizedCode, deviceName, screenTag, screenTags, true, null);
    }

    public KdsDevice bindMetadata(int shopId, String deviceCode, String deviceName,
                                  String screenTag, List<String> screenTags) {
        return bindInternal(shopId, deviceCode, deviceName, screenTag, screenTags, false, null);
    }

    private KdsDevice bindInternal(int shopId, String deviceCode, String deviceName,
                                   String screenTag, List<String> screenTags,
                                   boolean issueToken, String explicitToken) {
        if (deviceCode == null || deviceCode.trim().isEmpty()) {
            throw new IllegalArgumentException("device_code 不能为空");
        }
        if (!KdsScreenTag.isValid(screenTag)) {
            throw new IllegalArgumentException("无效的 screen_tag");
        }
        deviceCode = deviceCode.trim();
        KdsStation station = stationService.findByScreenTag(shopId, screenTag);
        KdsDevice device = deviceMapper.selectOne(new QueryWrapper<KdsDevice>().eq("device_code", deviceCode).last("LIMIT 1"));
        Date now = new Date();
        if (device == null) {
            device = new KdsDevice();
            device.setShop_id(shopId);
            device.setDevice_code(deviceCode);
            device.setCreated_at(now);
        } else if (!Integer.valueOf(shopId).equals(device.getShop_id())) {
            throw new IllegalArgumentException("设备已绑定其他门店");
        }
        device.setDevice_name(deviceName);
        device.setScreen_tag(screenTag);
        device.setStation_id(station != null ? station.getId() : null);
        String rawToken = null;
        Date tokenExpiresAt = device.getToken_expires_at();
        if (issueToken) {
            rawToken = explicitToken != null && !explicitToken.trim().isEmpty()
                    ? explicitToken.trim()
                    : generateToken();
            tokenExpiresAt = new Date(now.getTime() + Math.max(60L, deviceTokenTtlSeconds) * 1000L);
            device.setDevice_token(null);
            device.setToken_hash(hashToken(rawToken));
            device.setToken_expires_at(tokenExpiresAt);
            device.setToken_revoked_at(null);
        }
        device.setEnabled(1);
        device.setUpdated_at(now);
        if (device.getId() == null) {
            deviceMapper.insert(device);
        } else {
            com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<KdsDevice> uw =
                    new com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<KdsDevice>()
                            .eq("id", device.getId())
                            .set("token_revoked_at", null);
            if (issueToken) {
                uw.set("device_token", null);
            }
            deviceMapper.update(device, uw);
        }
        KdsDevice saved = enrichWorkflows(deviceMapper.selectById(device.getId()));
        if (issueToken && saved != null) {
            // Response-only credential. This assignment happens after the database write.
            saved.setDevice_token(rawToken);
            saved.setToken_expires_at(tokenExpiresAt);
        }
        if (screenTags != null && !screenTags.isEmpty()) {
            saveScreenSelection(device.getId(), screenTags);
            saved = enrichScreens(saved);
        }
        if (issueToken && eventPublisher != null) {
            eventPublisher.publishEvent(new KdsDeviceCredentialChangedEvent(shopId, deviceCode));
        }
        return saved;
    }

    /** 统一看板登录后保存多选流程，供 {@link #enrichWorkflows} 回显 */
    public void saveWorkflowSelection(Long deviceId, List<String> workflows) {
        if (deviceId == null) {
            return;
        }
        List<String> normalized = com.lanf.kds.KdsWorkflow.normalizeList(workflows);
        if (normalized.isEmpty()) {
            workflowStore.delete(deviceId);
        } else {
            workflowStore.save(deviceId, normalized);
        }
        if (deviceMapper != null) {
            KdsDevice dev = deviceMapper.selectById(deviceId);
            if (dev != null) {
                dev.setWorkflows_json(normalized.isEmpty() ? null : String.join(",", normalized));
                dev.setUpdated_at(new Date());
                deviceMapper.updateById(dev);
            }
        }
    }

    /** 保存设备可见岗（仅烤制三岗子集；全非法/空 → 删除记录回默认三岗）。 */
    public void saveScreenSelection(Long deviceId, List<String> screenTags) {
        if (deviceId == null) {
            return;
        }
        List<String> normalized = KdsDeviceScreenStore.normalizeList(screenTags);
        if (normalized.isEmpty()) {
            screenStore.delete(deviceId);
        } else {
            screenStore.save(deviceId, normalized);
        }
    }

    /** 统一看板取数用：设备可见烤制岗；未配置 → 默认三岗全选。 */
    public Set<String> screenTagsOf(KdsDevice device) {
        if (device != null && device.getId() != null) {
            List<String> tags = screenStore.get(device.getId());
            if (tags != null && !tags.isEmpty()) {
                return new LinkedHashSet<>(tags);
            }
        }
        return new LinkedHashSet<>(KdsScreenTag.PRODUCTION_GRILL_TAGS);
    }

    /** 回显设备可见岗（screen_tags）；无配置返回空列表（前端按空=三岗全选）。 */
    public KdsDevice enrichScreens(KdsDevice device) {
        if (device == null) {
            return null;
        }
        device.setScreen_tags(device.getId() != null ? screenStore.get(device.getId()) : null);
        return device;
    }

    @Transactional
    public void unbind(int shopId, String deviceCode) {
        deleteDevice(shopId, deviceCode);
    }

    @Transactional
    public boolean deleteDevice(int shopId, String deviceCode) {
        if (deviceCode == null || deviceCode.trim().isEmpty()) {
            return false;
        }
        KdsDevice device = deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("device_code", deviceCode.trim())
                .eq("shop_id", shopId)
                .last("LIMIT 1"));
        if (device != null) {
            return doDeleteDevice(shopId, device);
        }
        return false;
    }

    @Transactional
    public boolean deleteDeviceById(int shopId, Long deviceId) {
        if (deviceId == null) {
            return false;
        }
        KdsDevice device = deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("id", deviceId)
                .eq("shop_id", shopId)
                .last("LIMIT 1"));
        if (device != null) {
            return doDeleteDevice(shopId, device);
        }
        return false;
    }

    private boolean doDeleteDevice(int shopId, KdsDevice device) {
        Long deviceId = device.getId();
        String deviceCode = device.getDevice_code();

        workflowStore.delete(deviceId);
        screenStore.delete(deviceId);
        if (jdbc != null && deviceCode != null) {
            try {
                jdbc.update("DELETE FROM t_kds_device_pairing_ticket WHERE shop_id = ? AND device_code = ?",
                        shopId, deviceCode.trim());
            } catch (Exception ignored) {
            }
        }
        deviceMapper.deleteById(deviceId);
        if (eventPublisher != null && deviceCode != null) {
            eventPublisher.publishEvent(new KdsDeviceCredentialChangedEvent(shopId, deviceCode.trim()));
        }
        return true;
    }

    public KdsDevice findByToken(String token) {
        if (token == null || token.trim().isEmpty()) {
            return null;
        }
        Date now = new Date();
        KdsDevice device = deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("token_hash", hashToken(token.trim()))
                .eq("enabled", 1)
                .isNull("token_revoked_at")
                .gt("token_expires_at", now)
                .last("LIMIT 1"));
        if (device == null
                || device.getToken_revoked_at() != null
                || device.getToken_expires_at() == null
                || !device.getToken_expires_at().after(now)) {
            return null;
        }
        return enrichScreens(enrichWorkflows(device));
    }

    static String hashToken(String token) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(token.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(digest.length * 2);
            for (byte value : digest) {
                hex.append(String.format("%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static String generateToken() {
        byte[] entropy = new byte[32];
        TOKEN_RANDOM.nextBytes(entropy);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(entropy);
    }

    public void heartbeat(String deviceCode) {
        if (deviceCode == null || deviceCode.trim().isEmpty()) {
            return;
        }
        KdsDevice device = deviceMapper.selectOne(new QueryWrapper<KdsDevice>()
                .eq("device_code", deviceCode.trim())
                .last("LIMIT 1"));
        if (device != null) {
            device.setLast_heartbeat_at(new Date());
            deviceMapper.updateById(device);
        }
    }

    public KdsDevice enrichWorkflows(KdsDevice device) {
        if (device == null) {
            return null;
        }
        boolean prepEnabled = true;
        if (configService != null && device.getShop_id() != null) {
            prepEnabled = configService.isPrepWorkflowEnabled(device.getShop_id(), device.getStation_id());
        }
        if (device.getId() != null) {
            List<String> override = workflowStore.get(device.getId());
            if ((override == null || override.isEmpty()) && device.getWorkflows_json() != null && !device.getWorkflows_json().trim().isEmpty()) {
                String[] parts = device.getWorkflows_json().trim().split(",");
                List<String> fromDb = new ArrayList<>();
                for (String p : parts) {
                    if (!p.trim().isEmpty()) fromDb.add(p.trim());
                }
                if (!fromDb.isEmpty()) {
                    override = fromDb;
                    workflowStore.save(device.getId(), override);
                }
            }
            if (override != null && !override.isEmpty()) {
                if (!prepEnabled) {
                    List<String> filtered = new ArrayList<>();
                    for (String w : override) {
                        if (!com.lanf.kds.KdsWorkflow.PREP.equalsIgnoreCase(w)) {
                            filtered.add(w);
                        }
                    }
                    device.setWorkflows(filtered);
                } else {
                    device.setWorkflows(override);
                }
                return device;
            }
        }
        device.setWorkflows(com.lanf.kds.KdsWorkflow.resolveForDevice(device, prepEnabled));
        return device;
    }
}
