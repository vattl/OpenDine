package com.lanf.config;

import com.lanf.constant.ZsqSystemConfigKeys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 真省钱门店开关（持久化 {@code t_system_config}，键见 {@link ZsqSystemConfigKeys}）。
 * <ul>
 *   <li>{@code zsq.auto_api.enabled}：接单后是否自动发真省钱配送（false 时仅手动发单）</li>
 *   <li>{@code zsq.takeout_sync.enabled}：是否参与外卖配送状态定时同步</li>
 * </ul>
 * {@code shop_id=0} 为全门店默认；指定门店可覆盖。
 */
@Component
public class ZsqSystemSettings {

    /** shop_id=0 表示全门店默认 */
    public static final int GLOBAL_SHOP_ID = 0;

    private final boolean ymlDefaultAutoDispatch;
    private final boolean ymlDefaultTakeoutSync;

    private final ConcurrentHashMap<Integer, Boolean> autoDispatchByShop = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Integer, Boolean> takeoutSyncByShop = new ConcurrentHashMap<>();

    public ZsqSystemSettings(
            @Value("${zsq.auto-api-enabled:false}") boolean autoApiEnabled,
            @Value("${zsq.takeout-sync-enabled:true}") boolean takeoutSyncEnabled) {
        this.ymlDefaultAutoDispatch = autoApiEnabled;
        this.ymlDefaultTakeoutSync = takeoutSyncEnabled;
        autoDispatchByShop.put(GLOBAL_SHOP_ID, autoApiEnabled);
        takeoutSyncByShop.put(GLOBAL_SHOP_ID, takeoutSyncEnabled);
    }

    /** 接单后是否自动发真省钱配送 */
    public boolean isAutoDispatchEnabled(Integer shopId) {
        return resolveBool(autoDispatchByShop, shopId, ymlDefaultAutoDispatch);
    }

    /** 是否启用定时同步（全局默认，shop_id=0） */
    public boolean isTakeoutSyncEnabled() {
        return isTakeoutSyncEnabled(GLOBAL_SHOP_ID);
    }

    /** 指定门店是否参与定时同步；未配置时回退 shop_id=0 */
    public boolean isTakeoutSyncEnabled(Integer shopId) {
        return resolveBool(takeoutSyncByShop, shopId, ymlDefaultTakeoutSync);
    }

    public void setAutoDispatchEnabled(int shopId, boolean enabled) {
        autoDispatchByShop.put(normalizeShopId(shopId), enabled);
    }

    public void setTakeoutSyncEnabled(int shopId, boolean enabled) {
        takeoutSyncByShop.put(normalizeShopId(shopId), enabled);
    }

    public Map<String, Object> toPublicMap(Integer shopId) {
        int sid = normalizeShopId(shopId);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("shopId", sid);
        boolean auto = isAutoDispatchEnabled(sid == GLOBAL_SHOP_ID ? null : sid);
        m.put("autoDispatchEnabled", auto);
        m.put("autoApiEnabled", auto);
        m.put("takeoutSyncEnabled", isTakeoutSyncEnabled(sid == GLOBAL_SHOP_ID ? null : sid));
        return m;
    }

    public void applyFromKeyValue(int shopId, String key, String rawValue) {
        if (key == null) {
            return;
        }
        int sid = normalizeShopId(shopId);
        String k = key.trim();
        String v = rawValue == null ? "" : rawValue.trim();
        if (ZsqSystemConfigKeys.AUTO_API_ENABLED.equals(k)) {
            autoDispatchByShop.put(sid, parseBool(v, isAutoDispatchEnabled(sid == GLOBAL_SHOP_ID ? null : sid)));
        } else if (ZsqSystemConfigKeys.TAKEOUT_SYNC_ENABLED.equals(k)) {
            takeoutSyncByShop.put(sid, parseBool(v, isTakeoutSyncEnabled(sid == GLOBAL_SHOP_ID ? null : sid)));
        }
    }

    /** @deprecated 真省钱 HTTP /auto 接口不再单独开关，保留空实现避免调用方编译失败 */
    @Deprecated
    public void requireAutoApiEnabled() {
        // no-op：开关仅用于接单自动发单与定时同步
    }

    private boolean resolveBool(Map<Integer, Boolean> map, Integer shopId, boolean ymlDefault) {
        if (shopId != null) {
            Boolean shopVal = map.get(normalizeShopId(shopId));
            if (shopVal != null) {
                return shopVal;
            }
        }
        Boolean global = map.get(GLOBAL_SHOP_ID);
        if (global != null) {
            return global;
        }
        return ymlDefault;
    }

    private static int normalizeShopId(Integer shopId) {
        return shopId == null || shopId <= 0 ? GLOBAL_SHOP_ID : shopId;
    }

    private static boolean parseBool(String v, boolean def) {
        if (v.isEmpty()) {
            return def;
        }
        if ("1".equals(v) || "true".equalsIgnoreCase(v) || "yes".equalsIgnoreCase(v)) {
            return true;
        }
        if ("0".equals(v) || "false".equalsIgnoreCase(v) || "no".equalsIgnoreCase(v)) {
            return false;
        }
        return def;
    }
}
