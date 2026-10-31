package com.lanf.settings.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Shop;
import com.lanf.settings.entity.HqSettings;
import com.lanf.settings.entity.ShopSettingsOverride;
import com.lanf.settings.mapper.HqSettingsMapper;
import com.lanf.settings.mapper.ShopSettingsOverrideMapper;
import com.lanf.service.IShopService;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 门店设置：总部默认（t_hq_settings）+ 门店覆盖（t_shop_settings）+ 系统内置三级合并。
 * 契约见《系统设置后端协调文档》§1/§2：响应统一携带 source/version/updatedAt/updatedBy；
 * 更新携带 version 乐观锁，冲突返回 HTTP 409 + 最新版本摘要（SETTINGS_VERSION_CONFLICT）。
 */
@Service
public class ShopSettingsService {

    private static final Logger log = LoggerFactory.getLogger(ShopSettingsService.class);

    public static final String MODULE_STORE = "store";

    /** 生效优先级：SHOP 覆盖 > HEADQUARTERS 默认 > SYSTEM 内置 */
    public static final String SOURCE_SHOP = "SHOP";
    public static final String SOURCE_HQ = "HEADQUARTERS";
    public static final String SOURCE_SYSTEM = "SYSTEM";

    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;

    @Autowired
    private HqSettingsMapper hqSettingsMapper;
    @Autowired
    private ShopSettingsOverrideMapper shopSettingsOverrideMapper;
    @Autowired
    private IShopService shopService;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private JdbcTemplate jdbcTemplate;

    // ---------------- 查询 ----------------

    /** 门店设置详情（module=store）：基础资料 + 营业时段 + 营业日 + 来源/版本 */
    public Map<String, Object> getStoreSetting(int shopId) {
        return buildEffectiveSetting(shopId, MODULE_STORE);
    }

    /** 模块生效配置通用形态：meta（source/version/updatedAt/updatedBy）+ 合并后的配置节 */
    public Map<String, Object> buildEffectiveSetting(int shopId, String module) {
        ShopSettingsOverride override = findOverride(shopId, module);
        HqSettings hq = findHq(module);

        String source = override != null ? SOURCE_SHOP : (hq != null ? SOURCE_HQ : SOURCE_SYSTEM);
        int version = override != null && override.getVersion() != null ? override.getVersion()
                : (hq != null && hq.getVersion() != null ? hq.getVersion() : 0);
        LocalDateTime updatedAt = override != null ? override.getUpdated_at()
                : (hq != null ? hq.getUpdated_at() : null);
        Integer updatedBy = override != null ? override.getUpdated_by()
                : (hq != null ? hq.getUpdated_by() : null);

        Map<String, Object> merged = new LinkedHashMap<>();
        merged.putAll(systemDefaults(module));
        merged.putAll(parsePayload(hq != null ? hq.getPayload_json() : null));
        merged.putAll(parsePayload(override != null ? override.getPayload_json() : null));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("module", module);
        out.put("source", source);
        out.put("version", version);
        out.put("updatedAt", iso(updatedAt));
        out.put("updatedBy", updatedBy);
        if (MODULE_STORE.equals(module)) {
            out.put("basic", basicInfo(shopId));
        }
        for (Map.Entry<String, Object> e : merged.entrySet()) {
            if (!out.containsKey(e.getKey())) {
                out.put(e.getKey(), e.getValue());
            }
        }
        return out;
    }

    /** 生效版本的乐观锁基准：调用方所见 version 必须等于该值 */
    public int effectiveVersion(int shopId, String module) {
        ShopSettingsOverride override = findOverride(shopId, module);
        if (override != null && override.getVersion() != null) {
            return override.getVersion();
        }
        HqSettings hq = findHq(module);
        return hq != null && hq.getVersion() != null ? hq.getVersion() : 0;
    }

    public String effectiveSource(int shopId, String module) {
        ShopSettingsOverride override = findOverride(shopId, module);
        if (override != null) {
            return SOURCE_SHOP;
        }
        return findHq(module) != null ? SOURCE_HQ : SOURCE_SYSTEM;
    }

    // ---------------- 保存门店覆盖 ----------------

    /**
     * 保存/更新门店覆盖。body 接受可覆盖节（store 模块：businessHours/businessDays）及基础资料（basic 节点或顶层字段）。
     * expectedVersion 为调用方所见生效版本；不匹配返回 409 + 最新版本摘要。
     */
    public Map<String, Object> saveStoreOverride(int shopId, Integer expectedVersion,
                                                 Map<String, Object> body, Integer adminId) {
        if (body == null || body.isEmpty()) {
            throw new ApiException(400, "SETTINGS_PAYLOAD_EMPTY", "请求体不能为空");
        }
        if (expectedVersion == null) {
            throw new ApiException(400, "SETTINGS_VERSION_REQUIRED", "更新请求必须携带 version 乐观锁");
        }
        Map<String, Object> patch = new LinkedHashMap<>();
        if (body.containsKey("businessHours")) {
            patch.put("businessHours", validateBusinessHours(body.get("businessHours")));
        }
        if (body.containsKey("businessDays")) {
            patch.put("businessDays", validateBusinessDays(body.get("businessDays")));
        }

        // 基础资料更新支持（basic 节点或顶层店名/电话/地址/排序/经纬度等字段）
        boolean hasBasicInfo = body.containsKey("basic") || body.containsKey("name")
                || body.containsKey("code") || body.containsKey("phone") || body.containsKey("contact_phone")
                || body.containsKey("address") || body.containsKey("status") || body.containsKey("remark")
                || body.containsKey("openTime") || body.containsKey("open_time")
                || body.containsKey("closeTime") || body.containsKey("close_time")
                || body.containsKey("settleTime") || body.containsKey("settle_time")
                || body.containsKey("sort") || body.containsKey("sortOrder") || body.containsKey("sort_order") || body.containsKey("sorting")
                || body.containsKey("latitude") || body.containsKey("longitude")
                || body.containsKey("lat") || body.containsKey("lng")
                || body.containsKey("announcement") || body.containsKey("autoAccept") || body.containsKey("auto_accept")
                || body.containsKey("offlineCollectWechatPayload") || body.containsKey("offline_collect_wechat_payload")
                || body.containsKey("offlineCollectAlipayPayload") || body.containsKey("offline_collect_alipay_payload")
                || body.containsKey("offlineCollectWechatImagePath") || body.containsKey("offline_collect_wechat_image_path")
                || body.containsKey("offlineCollectAlipayImagePath") || body.containsKey("offline_collect_alipay_image_path");

        if (patch.isEmpty() && !hasBasicInfo) {
            throw new ApiException(400, "SETTINGS_NO_OVERRIDABLE_FIELDS",
                    "请求未包含可覆盖字段（businessHours/businessDays/basic）");
        }

        // 更新 t_shop 基础信息
        if (hasBasicInfo) {
            updateBasicShopInfo(shopId, body);
        }

        if (!patch.isEmpty()) {
            ShopSettingsOverride override = findOverride(shopId, MODULE_STORE);
            if (override == null) {
                int effective = effectiveVersion(shopId, MODULE_STORE);
                if (expectedVersion != effective) {
                    throw versionConflict(shopId, MODULE_STORE);
                }
                override = new ShopSettingsOverride();
                override.setShop_id(shopId);
                override.setModule(MODULE_STORE);
                override.setPayload_json(json(patch));
                override.setVersion(1);
                override.setUpdated_by(adminId);
                override.setUpdated_at(LocalDateTime.now(ZONE));
                shopSettingsOverrideMapper.insert(override);
            } else {
                if (!expectedVersion.equals(override.getVersion())) {
                    throw versionConflict(shopId, MODULE_STORE);
                }
                Map<String, Object> existing = parsePayload(override.getPayload_json());
                existing.putAll(patch);
                override.setPayload_json(json(existing));
                override.setVersion(override.getVersion() + 1);
                override.setUpdated_by(adminId);
                override.setUpdated_at(LocalDateTime.now(ZONE));
                shopSettingsOverrideMapper.updateById(override);
            }
        }
        log.info("[settings] store override saved: shop_id={}, version={}, admin={}", shopId, expectedVersion, adminId);
        return buildEffectiveSetting(shopId, MODULE_STORE);
    }

    @SuppressWarnings("unchecked")
    private void updateBasicShopInfo(int shopId, Map<String, Object> body) {
        Map<String, Object> basic = null;
        if (body.get("basic") instanceof Map) {
            basic = (Map<String, Object>) body.get("basic");
        }
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            return;
        }
        boolean modified = false;
        Map<String, Object> source = basic != null ? basic : body;

        if (source.containsKey("name") && source.get("name") != null) {
            String name = source.get("name").toString().trim();
            if (!name.isEmpty() && !name.equals(shop.getName())) {
                shop.setName(name);
                modified = true;
            }
        }
        if (source.containsKey("code") && source.get("code") != null) {
            String code = source.get("code").toString().trim();
            if (!code.equals(shop.getCode())) {
                shop.setCode(code);
                modified = true;
            }
        }
        if (source.containsKey("phone") && source.get("phone") != null) {
            String phone = source.get("phone").toString().trim();
            if (!phone.equals(shop.getContact_phone())) {
                shop.setContact_phone(phone);
                modified = true;
            }
        } else if (source.containsKey("contact_phone") && source.get("contact_phone") != null) {
            String phone = source.get("contact_phone").toString().trim();
            if (!phone.equals(shop.getContact_phone())) {
                shop.setContact_phone(phone);
                modified = true;
            }
        }
        if (source.containsKey("address") && source.get("address") != null) {
            String address = source.get("address").toString().trim();
            if (!address.equals(shop.getAddress())) {
                shop.setAddress(address);
                modified = true;
            }
        }
        if (source.containsKey("remark") && source.get("remark") != null) {
            String remark = source.get("remark").toString().trim();
            if (!remark.equals(shop.getRemark())) {
                shop.setRemark(remark);
                modified = true;
            }
        }
        if (source.containsKey("openTime") && source.get("openTime") != null) {
            String openTime = source.get("openTime").toString().trim();
            if (!openTime.equals(shop.getOpen_time())) {
                shop.setOpen_time(openTime);
                modified = true;
            }
        } else if (source.containsKey("open_time") && source.get("open_time") != null) {
            String openTime = source.get("open_time").toString().trim();
            if (!openTime.equals(shop.getOpen_time())) {
                shop.setOpen_time(openTime);
                modified = true;
            }
        }
        if (source.containsKey("closeTime") && source.get("closeTime") != null) {
            String closeTime = source.get("closeTime").toString().trim();
            if (!closeTime.equals(shop.getClose_time())) {
                shop.setClose_time(closeTime);
                modified = true;
            }
        } else if (source.containsKey("close_time") && source.get("close_time") != null) {
            String closeTime = source.get("close_time").toString().trim();
            if (!closeTime.equals(shop.getClose_time())) {
                shop.setClose_time(closeTime);
                modified = true;
            }
        }
        if (source.containsKey("settleTime") && source.get("settleTime") != null) {
            String settleTime = source.get("settleTime").toString().trim();
            if (!settleTime.isEmpty() && !settleTime.matches("^([01]\\d|2[0-3]):[0-5]\\d$")) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "settle_time 必须为 HH:mm");
            }
            String currentSettle = shop.getSettle_time() == null ? "" : shop.getSettle_time();
            if (!settleTime.equals(currentSettle)) {
                shop.setSettle_time(settleTime);
                modified = true;
            }
        } else if (source.containsKey("settle_time") && source.get("settle_time") != null) {
            String settleTime = source.get("settle_time").toString().trim();
            if (!settleTime.isEmpty() && !settleTime.matches("^([01]\\d|2[0-3]):[0-5]\\d$")) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "settle_time 必须为 HH:mm");
            }
            String currentSettle = shop.getSettle_time() == null ? "" : shop.getSettle_time();
            if (!settleTime.equals(currentSettle)) {
                shop.setSettle_time(settleTime);
                modified = true;
            }
        }
        if (source.containsKey("status") && source.get("status") instanceof Number) {
            int status = ((Number) source.get("status")).intValue();
            if (shop.getStatus() == null || status != shop.getStatus()) {
                shop.setStatus(status);
                modified = true;
            }
        }
        Object sortObj = source.containsKey("sort") ? source.get("sort")
                : (source.containsKey("sortOrder") ? source.get("sortOrder")
                : (source.containsKey("sort_order") ? source.get("sort_order") : source.get("sorting")));
        if (sortObj instanceof Number) {
            int sortVal = ((Number) sortObj).intValue();
            if (shop.getSort_order() == null || sortVal != shop.getSort_order()) {
                shop.setSort_order(sortVal);
                modified = true;
            }
        } else if (sortObj != null && !sortObj.toString().trim().isEmpty()) {
            try {
                int sortVal = Integer.parseInt(sortObj.toString().trim());
                if (shop.getSort_order() == null || sortVal != shop.getSort_order()) {
                    shop.setSort_order(sortVal);
                    modified = true;
                }
            } catch (Exception ignore) {
            }
        }
        if (source.containsKey("orderingOpen") && source.get("orderingOpen") instanceof Number) {
            int orderingOpen = ((Number) source.get("orderingOpen")).intValue();
            if (shop.getOrdering_open() == null || orderingOpen != shop.getOrdering_open()) {
                shop.setOrdering_open(orderingOpen);
                modified = true;
            }
        } else if (source.containsKey("ordering_open") && source.get("ordering_open") instanceof Number) {
            int orderingOpen = ((Number) source.get("ordering_open")).intValue();
            if (shop.getOrdering_open() == null || orderingOpen != shop.getOrdering_open()) {
                shop.setOrdering_open(orderingOpen);
                modified = true;
            }
        }
        if (source.containsKey("orderingReview") && source.get("orderingReview") instanceof Number) {
            int orderingReview = ((Number) source.get("orderingReview")).intValue();
            if (shop.getOrdering_review() == null || orderingReview != shop.getOrdering_review()) {
                shop.setOrdering_review(orderingReview);
                modified = true;
            }
        } else if (source.containsKey("ordering_review") && source.get("ordering_review") instanceof Number) {
            int orderingReview = ((Number) source.get("ordering_review")).intValue();
            if (shop.getOrdering_review() == null || orderingReview != shop.getOrdering_review()) {
                shop.setOrdering_review(orderingReview);
                modified = true;
            }
        }
        if (source.containsKey("shiftRequired") || source.containsKey("shift_required")) {
            Object v = source.containsKey("shiftRequired") ? source.get("shiftRequired") : source.get("shift_required");
            if (v instanceof Number) {
                int flag = ((Number) v).intValue();
                if (flag != 0 && flag != 1) {
                    throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "shift_required 只能为 0 或 1");
                }
                if (shop.getShift_required() == null || flag != shop.getShift_required()) {
                    shop.setShift_required(flag);
                    modified = true;
                }
            }
        }
        if (source.containsKey("settleRequired") || source.containsKey("settle_required")) {
            Object v = source.containsKey("settleRequired") ? source.get("settleRequired") : source.get("settle_required");
            if (v instanceof Number) {
                int flag = ((Number) v).intValue();
                if (flag != 0 && flag != 1) {
                    throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "settle_required 只能为 0 或 1");
                }
                if (shop.getSettle_required() == null || flag != shop.getSettle_required()) {
                    shop.setSettle_required(flag);
                    modified = true;
                }
            }
        }
        if (source.containsKey("regionId") && source.get("regionId") instanceof Number) {
            int regionId = ((Number) source.get("regionId")).intValue();
            if (shop.getRegion_id() == null || regionId != shop.getRegion_id()) {
                shop.setRegion_id(regionId);
                modified = true;
            }
        } else if (source.containsKey("region_id") && source.get("region_id") instanceof Number) {
            int regionId = ((Number) source.get("region_id")).intValue();
            if (shop.getRegion_id() == null || regionId != shop.getRegion_id()) {
                shop.setRegion_id(regionId);
                modified = true;
            }
        }
        Object latObj = source.containsKey("latitude") ? source.get("latitude") : source.get("lat");
        Object lngObj = source.containsKey("longitude") ? source.get("longitude") : source.get("lng");
        if (latObj != null && lngObj != null) {
            try {
                BigDecimal lat = new BigDecimal(latObj.toString().trim());
                BigDecimal lng = new BigDecimal(lngObj.toString().trim());
                if (!lat.equals(shop.getLatitude()) || !lng.equals(shop.getLongitude())) {
                    shop.setLatitude(lat);
                    shop.setLongitude(lng);
                    modified = true;
                }
                if (source.containsKey("coordinateType") && source.get("coordinateType") != null) {
                    shop.setCoordinate_type(source.get("coordinateType").toString().trim());
                } else if (source.containsKey("coordinate_type") && source.get("coordinate_type") != null) {
                    shop.setCoordinate_type(source.get("coordinate_type").toString().trim());
                }
            } catch (Exception ignore) {
            }
        }
        if (source.containsKey("offlineCollectWechatPayload") && source.get("offlineCollectWechatPayload") != null) {
            shop.setOffline_collect_wechat_payload(source.get("offlineCollectWechatPayload").toString().trim());
            modified = true;
        } else if (source.containsKey("offline_collect_wechat_payload") && source.get("offline_collect_wechat_payload") != null) {
            shop.setOffline_collect_wechat_payload(source.get("offline_collect_wechat_payload").toString().trim());
            modified = true;
        }
        if (source.containsKey("offlineCollectAlipayPayload") && source.get("offlineCollectAlipayPayload") != null) {
            shop.setOffline_collect_alipay_payload(source.get("offlineCollectAlipayPayload").toString().trim());
            modified = true;
        } else if (source.containsKey("offline_collect_alipay_payload") && source.get("offline_collect_alipay_payload") != null) {
            shop.setOffline_collect_alipay_payload(source.get("offline_collect_alipay_payload").toString().trim());
            modified = true;
        }
        if (source.containsKey("offlineCollectWechatImagePath") && source.get("offlineCollectWechatImagePath") != null) {
            shop.setOffline_collect_wechat_image_path(source.get("offlineCollectWechatImagePath").toString().trim());
            modified = true;
        } else if (source.containsKey("offline_collect_wechat_image_path") && source.get("offline_collect_wechat_image_path") != null) {
            shop.setOffline_collect_wechat_image_path(source.get("offline_collect_wechat_image_path").toString().trim());
            modified = true;
        }
        if (source.containsKey("offlineCollectAlipayImagePath") && source.get("offlineCollectAlipayImagePath") != null) {
            shop.setOffline_collect_alipay_image_path(source.get("offlineCollectAlipayImagePath").toString().trim());
            modified = true;
        } else if (source.containsKey("offline_collect_alipay_image_path") && source.get("offline_collect_alipay_image_path") != null) {
            shop.setOffline_collect_alipay_image_path(source.get("offline_collect_alipay_image_path").toString().trim());
            modified = true;
        }
        if (modified) {
            shopService.updateById(shop);
            log.info("[settings] basic shop info updated for shop_id={}", shopId);
        }
    }

    // ---------------- 恢复总部继承 ----------------

    /**
     * 删除门店覆盖行，恢复总部/系统默认。需二次确认（confirm=true）；
     * version 乐观锁针对覆盖行本身；覆盖行不存在时幂等返回当前生效配置。
     */
    public Map<String, Object> deleteOverride(int shopId, String module, Integer expectedVersion,
                                              boolean confirm, Integer adminId) {
        if (!confirm) {
            throw new ApiException(400, "SETTINGS_CONFIRM_REQUIRED", "恢复总部继承需要二次确认（confirm=true）");
        }
        ShopSettingsOverride override = findOverride(shopId, module);
        if (override == null) {
            return buildEffectiveSetting(shopId, module);
        }
        if (expectedVersion == null || !expectedVersion.equals(override.getVersion())) {
            throw versionConflict(shopId, module);
        }
        shopSettingsOverrideMapper.deleteById(override.getId());
        log.info("[settings] override removed: shop_id={}, module={}, admin={}", shopId, module, adminId);
        return buildEffectiveSetting(shopId, module);
    }

    // ---------------- 设置导航概览 ----------------

    /**
     * 设置导航概览：各模块的所需权限、当前管理员是否可见、来源、摘要、告警数。
     * 不返回支付敏感状态（文档 §2）。
     */
    public List<Map<String, Object>> overview(int shopId, Set<String> permissions) {
        List<Map<String, Object>> modules = new ArrayList<>();
        modules.add(moduleEntry(shopId, MODULE_STORE, "settings:view", permissions,
                "门店基础资料与营业时段", 0));
        modules.add(moduleEntry(shopId, "printing", "printing:view", permissions,
                "打印设备与规则", countOfflinePrintingDevices(shopId)));
        modules.add(moduleEntry(shopId, "payment", "payment:view", permissions,
                "支付渠道与能力", 0));
        modules.add(moduleEntry(shopId, "notifications", "notifications:view", permissions,
                "通知规则与发送记录", 0));
        modules.add(moduleEntry(shopId, "marketing", "marketing:view", permissions,
                "首单活动与核销", 0));
        modules.add(moduleEntry(shopId, "access", "access:view", permissions,
                "员工、角色与权限", 0));
        modules.add(moduleEntry(shopId, "inventory", "inventory:view", permissions,
                "原料、BOM 与采购调拨", 0));
        modules.add(moduleEntry(shopId, "reports", "report:view", permissions,
                "报表与导出任务", 0));
        modules.add(moduleEntry(shopId, "logs", "log:view", permissions,
                "操作日志与归档", 0));
        return modules;
    }

    private Map<String, Object> moduleEntry(int shopId, String module, String permission,
                                            Set<String> permissions, String summary, int alerts) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("module", module);
        m.put("permission", permission);
        m.put("permitted", permissions != null && permissions.contains(permission));
        m.put("source", effectiveSource(shopId, module));
        m.put("summary", summary);
        m.put("alerts", alerts);
        return m;
    }

    private int countOfflinePrintingDevices(int shopId) {
        try {
            Integer count = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM t_printing_device WHERE shop_id=? AND status IN ('OFFLINE','UNKNOWN')",
                    Integer.class, shopId);
            return count != null ? count : 0;
        } catch (DataAccessException e) {
            return 0; // 打印模块尚未部署/表不存在时概览不阻断
        }
    }

    // ---------------- 内部工具 ----------------

    private ShopSettingsOverride findOverride(int shopId, String module) {
        List<ShopSettingsOverride> rows = shopSettingsOverrideMapper.selectList(
                new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<ShopSettingsOverride>()
                        .eq("shop_id", shopId).eq("module", module));
        return rows.isEmpty() ? null : rows.get(0);
    }

    private HqSettings findHq(String module) {
        return hqSettingsMapper.selectById(module);
    }

    private ApiException versionConflict(int shopId, String module) {
        Map<String, Object> latest = new LinkedHashMap<>();
        latest.put("module", module);
        latest.put("source", effectiveSource(shopId, module));
        latest.put("version", effectiveVersion(shopId, module));
        ShopSettingsOverride override = findOverride(shopId, module);
        HqSettings hq = findHq(module);
        latest.put("updatedAt", iso(override != null ? override.getUpdated_at()
                : (hq != null ? hq.getUpdated_at() : null)));
        latest.put("updatedBy", override != null ? override.getUpdated_by()
                : (hq != null ? hq.getUpdated_by() : null));
        return new ApiException(409, "SETTINGS_VERSION_CONFLICT", "配置已被他人修改，请展示差异并重新加载", latest);
    }

    private Map<String, Object> systemDefaults(String module) {
        Map<String, Object> defaults = new LinkedHashMap<>();
        if (MODULE_STORE.equals(module)) {
            Map<String, Object> hours = new LinkedHashMap<>();
            hours.put("days", Arrays.asList(0, 1, 2, 3, 4, 5, 6));
            hours.put("open", "00:00");
            hours.put("close", "23:59");
            hours.put("enabled", true);
            defaults.put("businessHours", Collections.singletonList(hours));
            defaults.put("businessDays", Arrays.asList(0, 1, 2, 3, 4, 5, 6));
        }
        return defaults;
    }

    private Map<String, Object> basicInfo(int shopId) {
        Shop shop = shopService.getById(shopId);
        Map<String, Object> basic = new LinkedHashMap<>();
        basic.put("shopId", shopId);
        if (shop != null) {
            basic.put("name", shop.getName());
            basic.put("code", shop.getCode());
            basic.put("address", shop.getAddress());
            basic.put("phone", shop.getContact_phone());
            basic.put("contact_phone", shop.getContact_phone());
            basic.put("openTime", shop.getOpen_time());
            basic.put("open_time", shop.getOpen_time());
            basic.put("closeTime", shop.getClose_time());
            basic.put("close_time", shop.getClose_time());
            basic.put("settleTime", shop.getSettle_time());
            basic.put("settle_time", shop.getSettle_time());
            basic.put("status", shop.getStatus());
            int sort = shop.getSort_order() != null ? shop.getSort_order() : 0;
            basic.put("sort", sort);
            basic.put("sortOrder", sort);
            basic.put("sort_order", sort);
            basic.put("latitude", shop.getLatitude());
            basic.put("longitude", shop.getLongitude());
            basic.put("lat", shop.getLatitude());
            basic.put("lng", shop.getLongitude());
            basic.put("remark", shop.getRemark() != null ? shop.getRemark() : "");
            basic.put("coordinateType", shop.getCoordinate_type() != null ? shop.getCoordinate_type() : "gcj02");
            basic.put("coordinate_type", shop.getCoordinate_type() != null ? shop.getCoordinate_type() : "gcj02");
            basic.put("orderingOpen", shop.getOrdering_open() != null ? shop.getOrdering_open() : 1);
            basic.put("ordering_open", shop.getOrdering_open() != null ? shop.getOrdering_open() : 1);
            basic.put("orderingReview", shop.getOrdering_review() != null ? shop.getOrdering_review() : 1);
            basic.put("ordering_review", shop.getOrdering_review() != null ? shop.getOrdering_review() : 1);
            basic.put("shiftRequired", shop.getShift_required() != null ? shop.getShift_required() : 0);
            basic.put("shift_required", shop.getShift_required() != null ? shop.getShift_required() : 0);
            basic.put("settleRequired", shop.getSettle_required() != null ? shop.getSettle_required() : 0);
            basic.put("settle_required", shop.getSettle_required() != null ? shop.getSettle_required() : 0);
            basic.put("regionId", shop.getRegion_id());
            basic.put("region_id", shop.getRegion_id());

            // 线下收款码相关状态与路径
            boolean hasWechat = (shop.getOffline_collect_wechat_payload() != null && !shop.getOffline_collect_wechat_payload().trim().isEmpty())
                    || (shop.getOffline_collect_wechat_image_path() != null && !shop.getOffline_collect_wechat_image_path().trim().isEmpty());
            boolean hasAlipay = (shop.getOffline_collect_alipay_payload() != null && !shop.getOffline_collect_alipay_payload().trim().isEmpty())
                    || (shop.getOffline_collect_alipay_image_path() != null && !shop.getOffline_collect_alipay_image_path().trim().isEmpty());

            basic.put("offlineCollectWechatPayload", shop.getOffline_collect_wechat_payload());
            basic.put("offline_collect_wechat_payload", shop.getOffline_collect_wechat_payload());
            basic.put("offlineCollectAlipayPayload", shop.getOffline_collect_alipay_payload());
            basic.put("offline_collect_alipay_payload", shop.getOffline_collect_alipay_payload());
            basic.put("offlineCollectWechatImagePath", shop.getOffline_collect_wechat_image_path());
            basic.put("offline_collect_wechat_image_path", shop.getOffline_collect_wechat_image_path());
            basic.put("offlineCollectAlipayImagePath", shop.getOffline_collect_alipay_image_path());
            basic.put("offline_collect_alipay_image_path", shop.getOffline_collect_alipay_image_path());
            basic.put("wechatQrConfigured", hasWechat);
            basic.put("alipayQrConfigured", hasAlipay);
            basic.put("hasWechatQr", hasWechat);
            basic.put("hasAlipayQr", hasAlipay);
            basic.put("wechatQrImageUrl", shop.getOffline_collect_wechat_image_path());
            basic.put("alipayQrImageUrl", shop.getOffline_collect_alipay_image_path());
        }
        return basic;
    }

    private Map<String, Object> parsePayload(String json) {
        if (StringUtil.isEmpty(json)) {
            return new LinkedHashMap<>();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<LinkedHashMap<String, Object>>() {
            });
        } catch (Exception e) {
            log.warn("[settings] payload 解析失败，忽略该层: {}", e.getMessage());
            return new LinkedHashMap<>();
        }
    }

    private String json(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            throw new ApiException(500, "SETTINGS_SERIALIZE_FAILED", "配置序列化失败");
        }
    }

    private String iso(LocalDateTime time) {
        return time == null ? null : time.atZone(ZONE).format(ISO);
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> validateBusinessHours(Object raw) {
        if (!(raw instanceof List) || ((List<Object>) raw).isEmpty()) {
            throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "businessHours 必须为非空数组");
        }
        List<Map<String, Object>> hours = (List<Map<String, Object>>) raw;
        for (Map<String, Object> h : hours) {
            Object days = h.get("days");
            Set<Integer> daySet = toDaySet(days, "businessHours[].days");
            if (daySet.isEmpty()) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "businessHours[].days 不能为空");
            }
            String open = String.valueOf(h.get("open"));
            String close = String.valueOf(h.get("close"));
            if (!open.matches("^([01]\\d|2[0-3]):[0-5]\\d$") || !close.matches("^([01]\\d|2[0-3]):[0-5]\\d$")) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "businessHours[].open/close 必须为 HH:mm");
            }
            if (open.compareTo(close) >= 0) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "businessHours[].open 必须早于 close");
            }
        }
        return hours;
    }

    @SuppressWarnings("unchecked")
    private List<Integer> validateBusinessDays(Object raw) {
        if (!(raw instanceof List) || ((List<Object>) raw).isEmpty()) {
            throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", "businessDays 必须为非空数组");
        }
        Set<Integer> daySet = toDaySet(raw, "businessDays");
        List<Integer> days = new ArrayList<>(daySet);
        java.util.Collections.sort(days);
        return days;
    }

    @SuppressWarnings("unchecked")
    private Set<Integer> toDaySet(Object raw, String field) {
        Set<Integer> out = new HashSet<>();
        if (!(raw instanceof List)) {
            throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", field + " 必须为数组");
        }
        for (Object o : (List<Object>) raw) {
            int day;
            try {
                day = ((Number) o).intValue();
            } catch (Exception e) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", field + " 必须为 0-6 的整数（0=周日）");
            }
            if (day < 0 || day > 6) {
                throw new ApiException(400, "SETTINGS_VALIDATION_FAILED", field + " 取值必须为 0-6（0=周日）");
            }
            out.add(day);
        }
        return out;
    }
}
