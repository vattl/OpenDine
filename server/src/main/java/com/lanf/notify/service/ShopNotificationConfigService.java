package com.lanf.notify.service;

import com.lanf.entity.ShopNotificationConfig;
import com.lanf.mapper.ShopNotificationConfigMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 门店消息通知与出餐超时动态阈值配置服务。
 */
@Service
public class ShopNotificationConfigService {

    public static final int DEFAULT_PREP_TIMEOUT_ENABLED = 1;
    public static final int DEFAULT_PREP_TIMEOUT_MINUTES = 15;
    public static final int MIN_PREP_TIMEOUT_MINUTES = 5;
    public static final int MAX_PREP_TIMEOUT_MINUTES = 120;

    public static final int DEFAULT_REPEAT_INTERVAL_SECONDS = 60;
    public static final int MIN_REPEAT_INTERVAL_SECONDS = 15;
    public static final int MAX_REPEAT_INTERVAL_SECONDS = 600;

    private final ShopNotificationConfigMapper configMapper;
    private final ConcurrentHashMap<Integer, ShopNotificationConfig> configCache = new ConcurrentHashMap<>();

    @Autowired
    public ShopNotificationConfigService(ShopNotificationConfigMapper configMapper) {
        this.configMapper = configMapper;
    }

    public ShopNotificationConfig getOrDefaultConfig(Integer shopId) {
        int normalizedShopId = (shopId != null && shopId > 0) ? shopId : 1;
        ShopNotificationConfig cached = configCache.get(normalizedShopId);
        if (cached != null) {
            return copyOf(cached);
        }
        ShopNotificationConfig dbRecord = null;
        if (configMapper != null) {
            try {
                dbRecord = configMapper.selectById(normalizedShopId);
            } catch (Exception ignored) {
                // Table may not exist in lightweight unit test environments
            }
        }
        if (dbRecord == null) {
            dbRecord = defaultConfig(normalizedShopId);
        } else {
            normalizeDefaults(dbRecord, normalizedShopId);
        }
        configCache.put(normalizedShopId, copyOf(dbRecord));
        return copyOf(dbRecord);
    }

    @Transactional
    public ShopNotificationConfig saveConfig(Integer shopId, Boolean prepTimeoutEnabled,
                                             Integer prepTimeoutMinutes, Integer repeatIntervalSeconds,
                                             Integer operatorAdminId) {
        if (shopId == null || shopId <= 0) {
            throw new IllegalArgumentException("shop_id 不能为空且必须大于 0");
        }
        ShopNotificationConfig current = getOrDefaultConfig(shopId);

        int enabled = prepTimeoutEnabled != null
                ? (prepTimeoutEnabled ? 1 : 0)
                : (current.getPrep_timeout_enabled() != null ? current.getPrep_timeout_enabled() : DEFAULT_PREP_TIMEOUT_ENABLED);

        int minutes = prepTimeoutMinutes != null
                ? prepTimeoutMinutes
                : (current.getPrep_timeout_minutes() != null ? current.getPrep_timeout_minutes() : DEFAULT_PREP_TIMEOUT_MINUTES);
        if (minutes < MIN_PREP_TIMEOUT_MINUTES || minutes > MAX_PREP_TIMEOUT_MINUTES) {
            throw new IllegalArgumentException(
                    "出餐超时阈值必须在 " + MIN_PREP_TIMEOUT_MINUTES + " 到 " + MAX_PREP_TIMEOUT_MINUTES + " 分钟之间");
        }

        int repeatSec = repeatIntervalSeconds != null
                ? repeatIntervalSeconds
                : (current.getTimeout_repeat_interval_seconds() != null
                        ? current.getTimeout_repeat_interval_seconds()
                        : DEFAULT_REPEAT_INTERVAL_SECONDS);
        if (repeatSec < MIN_REPEAT_INTERVAL_SECONDS || repeatSec > MAX_REPEAT_INTERVAL_SECONDS) {
            throw new IllegalArgumentException(
                    "重复语音提醒间隔必须在 " + MIN_REPEAT_INTERVAL_SECONDS + " 到 " + MAX_REPEAT_INTERVAL_SECONDS + " 秒之间");
        }

        Date now = new Date();
        ShopNotificationConfig entity = new ShopNotificationConfig();
        entity.setShop_id(shopId);
        entity.setPrep_timeout_enabled(enabled);
        entity.setPrep_timeout_minutes(minutes);
        entity.setTimeout_repeat_interval_seconds(repeatSec);
        entity.setUpdated_by(operatorAdminId);
        entity.setUpdated_at(now);

        if (configMapper != null) {
            ShopNotificationConfig existing = configMapper.selectById(shopId);
            if (existing == null) {
                configMapper.insert(entity);
            } else {
                configMapper.updateById(entity);
            }
        }
        configCache.put(shopId, copyOf(entity));
        return copyOf(entity);
    }

    public Map<String, Object> toConfigMap(ShopNotificationConfig cfg) {
        Map<String, Object> map = new LinkedHashMap<>();
        if (cfg == null) {
            cfg = defaultConfig(1);
        }
        boolean enabled = cfg.getPrep_timeout_enabled() == null || cfg.getPrep_timeout_enabled() != 0;
        int minutes = cfg.getPrep_timeout_minutes() != null ? cfg.getPrep_timeout_minutes() : DEFAULT_PREP_TIMEOUT_MINUTES;
        int repeatSec = cfg.getTimeout_repeat_interval_seconds() != null
                ? cfg.getTimeout_repeat_interval_seconds()
                : DEFAULT_REPEAT_INTERVAL_SECONDS;
        map.put("shop_id", cfg.getShop_id());
        map.put("shopId", cfg.getShop_id());
        map.put("prep_timeout_enabled", enabled);
        map.put("prepTimeoutEnabled", enabled);
        map.put("prep_timeout_minutes", minutes);
        map.put("prepTimeoutMinutes", minutes);
        map.put("timeout_repeat_interval_seconds", repeatSec);
        map.put("timeoutRepeatIntervalSeconds", repeatSec);
        map.put("min_prep_timeout_minutes", MIN_PREP_TIMEOUT_MINUTES);
        map.put("max_prep_timeout_minutes", MAX_PREP_TIMEOUT_MINUTES);
        map.put("updated_by", cfg.getUpdated_by());
        map.put("updated_at", cfg.getUpdated_at());
        return map;
    }

    public void evictCache(Integer shopId) {
        if (shopId == null) {
            configCache.clear();
        } else {
            configCache.remove(shopId);
        }
    }

    private static ShopNotificationConfig defaultConfig(int shopId) {
        ShopNotificationConfig cfg = new ShopNotificationConfig();
        cfg.setShop_id(shopId);
        cfg.setPrep_timeout_enabled(DEFAULT_PREP_TIMEOUT_ENABLED);
        cfg.setPrep_timeout_minutes(DEFAULT_PREP_TIMEOUT_MINUTES);
        cfg.setTimeout_repeat_interval_seconds(DEFAULT_REPEAT_INTERVAL_SECONDS);
        return cfg;
    }

    private static void normalizeDefaults(ShopNotificationConfig cfg, int shopId) {
        if (cfg.getShop_id() == null) {
            cfg.setShop_id(shopId);
        }
        if (cfg.getPrep_timeout_enabled() == null) {
            cfg.setPrep_timeout_enabled(DEFAULT_PREP_TIMEOUT_ENABLED);
        }
        if (cfg.getPrep_timeout_minutes() == null || cfg.getPrep_timeout_minutes() < MIN_PREP_TIMEOUT_MINUTES) {
            cfg.setPrep_timeout_minutes(DEFAULT_PREP_TIMEOUT_MINUTES);
        }
        if (cfg.getTimeout_repeat_interval_seconds() == null || cfg.getTimeout_repeat_interval_seconds() < MIN_REPEAT_INTERVAL_SECONDS) {
            cfg.setTimeout_repeat_interval_seconds(DEFAULT_REPEAT_INTERVAL_SECONDS);
        }
    }

    private static ShopNotificationConfig copyOf(ShopNotificationConfig src) {
        ShopNotificationConfig dst = new ShopNotificationConfig();
        dst.setShop_id(src.getShop_id());
        dst.setPrep_timeout_enabled(src.getPrep_timeout_enabled());
        dst.setPrep_timeout_minutes(src.getPrep_timeout_minutes());
        dst.setTimeout_repeat_interval_seconds(src.getTimeout_repeat_interval_seconds());
        dst.setUpdated_by(src.getUpdated_by());
        dst.setUpdated_at(src.getUpdated_at());
        return dst;
    }
}
