package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.config.InvitePosterSettings;
import com.lanf.config.InviteFirstOrderRewardSettings;
import com.lanf.payment.config.PaymentConfigSync;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.config.ZsqSystemSettings;
import com.lanf.constant.InviteFirstOrderRewardConfigKeys;
import com.lanf.constant.ZsqSystemConfigKeys;
import com.lanf.entity.R;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.util.StringUtil;
import com.lanf.util.SystemConfigTableSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.time.LocalTime;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.Map;

/**
 * 基础配置管理（打印机、邀请海报等），供运营后台前端修改配置使用。
 * 注意：当前修改仅在内存中生效，应用重启后以 application.yml 中配置为准。
 * 权限控制依赖 admin:manage（见 docs/权限设计.md、openapi.yaml 与 t_api_permission）。
 */
@RestController
@RequestMapping("/admin/config")
public class AdminConfigController {

    @Autowired
    private InvitePosterSettings invitePosterSettings;
    @Autowired
    private SystemConfigMapper systemConfigMapper;
    @Autowired
    private PaymentNinefoldService paymentNinefoldService;
    @Autowired
    private PaymentConfigSync paymentConfigSync;
    @Autowired
    private InviteFirstOrderRewardSettings inviteFirstOrderRewardSettings;
    @Autowired
    private ZsqSystemSettings zsqSystemSettings;
    @Autowired
    private SystemConfigTableSupport systemConfigTableSupport;
    @Autowired
    private AdminShopScopeGuard adminShopScopeGuard;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;

    /**
     * 获取微信统一下单「夜间九折」规则（全店默认 {@code shop_id=0}，兼容旧路径）。
     * @deprecated 自 v1.2.132 起废弃，请统一使用 {@code GET /admin/payment/ninefold}。
     */
    @Deprecated
    @GetMapping("/wechat-prepay-ninefold")
    public R getWechatPrepayNineFold(@RequestParam(required = false) Integer shopId) {
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
        return scopeError != null ? scopeError : R.ok(paymentNinefoldService.toAdminMap(target[0]));
    }

    /**
     * 更新夜间九折（全店默认或指定 shopId；写入 {@code t_payment_ninefold_config}）。
     * @deprecated 自 v1.2.132 起废弃，请统一使用 {@code PUT /admin/payment/ninefold}。
     */
    @Deprecated
    @PutMapping("/wechat-prepay-ninefold")
    @AuditLog(module = "config", action = "admin_config_wechat_prepay_ninefold")
    public R putWechatPrepayNineFold(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(parseShopIdFromBody(body), target);
        if (scopeError != null) {
            return scopeError;
        }
        int sid = target[0];
        try {
            paymentNinefoldService.upsert(sid, body);
            paymentConfigSync.reloadShop(sid);
            return R.ok(paymentNinefoldService.toAdminMap(sid));
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 邀请好友首单余额返利：开关 + 实付比例（%）。
     */
    @GetMapping("/invite-first-order-balance-reward")
    public R getInviteFirstOrderBalanceReward() {
        R scopeError = adminShopScopeGuard.requireHeadquarters();
        if (scopeError != null) return scopeError;
        return R.ok(inviteFirstOrderRewardSettings.toPublicMap());
    }

    /**
     * 更新首单余额返利规则：写入 t_system_config 并立即更新内存。
     */
    @PutMapping("/invite-first-order-balance-reward")
    @AuditLog(module = "config", action = "admin_config_invite_first_order_reward")
    public R putInviteFirstOrderBalanceReward(@RequestBody Map<String, Object> body) {
        R scopeError = adminShopScopeGuard.requireHeadquarters();
        if (scopeError != null) return scopeError;
        if (body == null) {
            return R.error("请求体不能为空");
        }
        if (body.containsKey("enabled")) {
            boolean v = parseBoolFlexible(body.get("enabled"), inviteFirstOrderRewardSettings.isEnabled());
            inviteFirstOrderRewardSettings.setEnabled(v);
            upsertConfig(InviteFirstOrderRewardConfigKeys.ENABLED, v ? "true" : "false", "邀请好友首单余额返利开关");
        }
        if (body.containsKey("rewardPercent")) {
            Double d = parseDoubleFlexible(body.get("rewardPercent"));
            if (d != null) {
                if (d < 0d || d > 100d) {
                    return R.error("rewardPercent 须在 0～100 之间");
                }
                inviteFirstOrderRewardSettings.setRewardPercent(d);
                upsertConfig(InviteFirstOrderRewardConfigKeys.PERCENT,
                        String.valueOf(inviteFirstOrderRewardSettings.getRewardPercent()),
                        "邀请好友首单余额返利比例(%)");
            }
        }
        return R.ok(inviteFirstOrderRewardSettings.toPublicMap());
    }

    /**
     * 真省钱开关（t_system_config，按门店 shop_id；0=全门店默认）。
     * {@code autoDispatchEnabled=false} 时接单后不自动发配送，须手动 {@code POST /admin/takeout/delivery/zsq/dispatch}。
     */
    @GetMapping("/zsq-auto-api")
    public R getZsqAutoApi(@RequestParam(required = false) Integer shopId) {
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
        return scopeError != null ? scopeError : R.ok(zsqSystemSettings.toPublicMap(target[0]));
    }

    /**
     * 更新真省钱开关：写入 t_system_config（含 shop_id）并立即生效。
     */
    @PutMapping("/zsq-auto-api")
    @AuditLog(module = "config", action = "admin_config_zsq_auto_api")
    public R putZsqAutoApi(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(parseShopIdFromBody(body), target);
        if (scopeError != null) return scopeError;
        int shopId = target[0];
        if (body.containsKey("autoDispatchEnabled") || body.containsKey("autoApiEnabled")) {
            Object raw = body.containsKey("autoDispatchEnabled") ? body.get("autoDispatchEnabled") : body.get("autoApiEnabled");
            boolean v = parseBoolFlexible(raw, zsqSystemSettings.isAutoDispatchEnabled(shopId == 0 ? null : shopId));
            zsqSystemSettings.setAutoDispatchEnabled(shopId, v);
            try {
                upsertConfig(ZsqSystemConfigKeys.AUTO_API_ENABLED, v ? "1" : "0",
                        "接单后自动发真省钱配送", shopId);
            } catch (IllegalStateException ex) {
                return R.error(ex.getMessage());
            }
        }
        if (body.containsKey("takeoutSyncEnabled")) {
            boolean v = parseBoolFlexible(body.get("takeoutSyncEnabled"),
                    zsqSystemSettings.isTakeoutSyncEnabled(shopId == 0 ? null : shopId));
            zsqSystemSettings.setTakeoutSyncEnabled(shopId, v);
            try {
                upsertConfig(ZsqSystemConfigKeys.TAKEOUT_SYNC_ENABLED, v ? "1" : "0",
                        "外卖真省钱配送状态定时同步", shopId);
            } catch (IllegalStateException ex) {
                return R.error(ex.getMessage());
            }
        }
        return R.ok(zsqSystemSettings.toPublicMap(shopId));
    }

    /**
     * 查询会员余额跨店使用开关（单店/连锁共存配置）。
     * 1=允许跨店互通（连锁共享），0=禁止跨店（单店专属）。
     */
    @GetMapping("/member-balance-cross-shop")
    public R getMemberBalanceCrossShop(@RequestParam(required = false) Integer shopId) {
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
        if (scopeError != null) return scopeError;
        int targetShopId = target[0];
        boolean enabled = shopMemberWalletService != null
                ? shopMemberWalletService.isCrossShopBalanceEnabled(targetShopId)
                : true;
        Map<String, Object> res = new HashMap<>();
        res.put("shopId", targetShopId);
        res.put("crossShopBalanceEnabled", enabled);
        return R.ok(res);
    }

    /**
     * 更新会员余额跨店使用开关。
     */
    @PutMapping("/member-balance-cross-shop")
    @AuditLog(module = "config", action = "admin_config_member_balance_cross_shop")
    public R putMemberBalanceCrossShop(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(parseShopIdFromBody(body), target);
        if (scopeError != null) return scopeError;
        int targetShopId = target[0];
        Object rawEnabled = body.get("crossShopBalanceEnabled");
        if (rawEnabled == null) {
            rawEnabled = body.get("enabled");
        }
        boolean enabled = parseBoolFlexible(rawEnabled, true);
        if (shopMemberWalletService != null) {
            shopMemberWalletService.setCrossShopBalanceEnabled(targetShopId, enabled);
        }
        Map<String, Object> res = new HashMap<>();
        res.put("shopId", targetShopId);
        res.put("crossShopBalanceEnabled", enabled);
        return R.ok(res);
    }

    private static Integer parseShopIdFromBody(Map<String, Object> body) {
        if (body == null) {
            return null;
        }
        Object raw = body.get("shopId");
        if (raw == null) {
            raw = body.get("shop_id");
        }
        if (raw instanceof Number) {
            return ((Number) raw).intValue();
        }
        if (raw != null && !StringUtil.isEmpty(raw.toString())) {
            try {
                return Integer.parseInt(raw.toString().trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }

    private static boolean parseBoolFlexible(Object raw, boolean def) {
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        if (raw instanceof Number) {
            return ((Number) raw).intValue() != 0;
        }
        if (raw != null && !StringUtil.isEmpty(raw.toString())) {
            String s = raw.toString().trim();
            if ("1".equals(s) || "true".equalsIgnoreCase(s)) {
                return true;
            }
            if ("0".equals(s) || "false".equalsIgnoreCase(s)) {
                return false;
            }
        }
        return def;
    }

    private static Double parseDoubleFlexible(Object raw) {
        if (raw instanceof Number) {
            return ((Number) raw).doubleValue();
        }
        if (raw != null && !StringUtil.isEmpty(raw.toString())) {
            try {
                return Double.parseDouble(raw.toString().trim());
            } catch (NumberFormatException ignore) {
            }
        }
        return null;
    }

    private static LocalTime parseLocalTimeFlexible(Object raw) {
        if (raw == null || StringUtil.isEmpty(raw.toString())) {
            return null;
        }
        try {
            return LocalTime.parse(raw.toString().trim());
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * 获取邀请海报配置（背景图路径 + 二维码位置/尺寸）。
     */
    @GetMapping("/invite-poster")
    public R getInvitePosterConfig() {
        R scopeError = adminShopScopeGuard.requireHeadquarters();
        if (scopeError != null) return scopeError;
        Map<String, Object> data = new HashMap<>();
        InvitePosterSettings.Background bg = invitePosterSettings.getBackground();
        InvitePosterSettings.Qr qr = invitePosterSettings.getQr();
        data.put("backgroundPath", bg != null ? bg.getPath() : null);
        Map<String, Object> qrMap = new HashMap<>();
        if (qr != null) {
            qrMap.put("x", qr.getX());
            qrMap.put("y", qr.getY());
            qrMap.put("size", qr.getSize());
        }
        data.put("qr", qrMap);
        return R.ok(data);
    }

    /**
     * 更新邀请海报配置（仅内存生效）。
     */
    @PutMapping("/invite-poster")
    @AuditLog(module = "config", action = "admin_config_invite_poster")
    public R updateInvitePosterConfig(@RequestBody Map<String, Object> body) {
        R scopeError = adminShopScopeGuard.requireHeadquarters();
        if (scopeError != null) return scopeError;
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Object bgPath = body.get("backgroundPath");
        if (bgPath != null && !StringUtil.isEmpty(bgPath.toString())) {
            String v = bgPath.toString().trim();
            invitePosterSettings.getBackground().setPath(v);
            upsertConfig("invite.poster.background.path", v, "邀请海报背景图路径");
        }
        Object qrObj = body.get("qr");
        if (qrObj instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> qrMap = (Map<String, Object>) qrObj;
            Object x = qrMap.get("x");
            Object y = qrMap.get("y");
            Object size = qrMap.get("size");
            if (x instanceof Number) {
                int v = ((Number) x).intValue();
                invitePosterSettings.getQr().setX(v);
                upsertConfig("invite.poster.qr.x", String.valueOf(v), "邀请海报二维码X坐标");
            }
            if (y instanceof Number) {
                int v = ((Number) y).intValue();
                invitePosterSettings.getQr().setY(v);
                upsertConfig("invite.poster.qr.y", String.valueOf(v), "邀请海报二维码Y坐标");
            }
            if (size instanceof Number) {
                int v = ((Number) size).intValue();
                invitePosterSettings.getQr().setSize(v);
                upsertConfig("invite.poster.qr.size", String.valueOf(v), "邀请海报二维码尺寸");
            }
        }
        return R.ok();
    }

    private void upsertConfig(String key, String value, String remark) {
        upsertConfig(key, value, remark, ZsqSystemSettings.GLOBAL_SHOP_ID);
    }

    /**
     * 将配置写入 t_system_config（存在则更新，不存在则插入）。
     */
    private void upsertConfig(String key, String value, String remark, int shopId) {
        if (!systemConfigTableSupport.hasShopIdColumn()) {
            if (shopId != ZsqSystemSettings.GLOBAL_SHOP_ID) {
                throw new IllegalStateException("当前数据库 t_system_config 缺少 shop_id 列，请先执行 docs/db_migration_system_config_shop_id.sql");
            }
            SystemConfig existing = systemConfigMapper.selectLegacyByKey(key);
            if (existing == null) {
                systemConfigMapper.insertLegacy(key, value, remark);
            } else {
                systemConfigMapper.updateLegacy(key, value, remark);
            }
            return;
        }
        SystemConfig existing = systemConfigMapper.selectByShopAndKey(shopId, key);
        if (existing == null) {
            SystemConfig cfg = new SystemConfig();
            cfg.setShop_id(shopId);
            cfg.setConfig_key(key);
            cfg.setConfig_value(value);
            cfg.setRemark(remark);
            systemConfigMapper.insert(cfg);
        } else {
            existing.setConfig_value(value);
            if (remark != null) {
                existing.setRemark(remark);
            }
            systemConfigMapper.updateById(existing);
        }
    }
}

