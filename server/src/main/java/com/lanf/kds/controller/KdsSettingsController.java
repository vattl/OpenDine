package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.event.KdsConfigChangedEvent;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;

/**
 * KDS 本机/门店规则设置（openapi /kds/settings）。
 * 读写都以设备 token 绑定的门店为唯一权威，不向设备端序列化 PIN 等管理字段。
 */
@RestController
@RequestMapping("/kds/settings")
public class KdsSettingsController {

    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private HttpServletRequest request;
    @Autowired
    private ApplicationEventPublisher eventPublisher;

    @GetMapping
    public R get(@RequestParam(required = false, name = "shop_id") Integer shopId,
                 @RequestParam(required = false, name = "shopId") Integer shopIdCamel) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer requestedShopId = shopId != null ? shopId : shopIdCamel;
            if (requestedShopId != null && !requestedShopId.equals(device.getShop_id())) {
                return R.error(403, "KDS 设备不属于请求的门店");
            }
            KdsShopConfig cfg = configService.getOrDefault(device.getShop_id());
            return R.ok().put("settings", toSettings(cfg));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        }
    }

    @PutMapping
    public R put(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            return saveForDevice(device, body);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /** Shared cloud-authority write boundary used by both legacy and V2 routes. */
    public R saveForDevice(KdsDevice device, Map<String, Object> body) {
        int shopId = device.getShop_id();
        KdsShopConfig input = new KdsShopConfig();
        input.setShop_id(shopId);
        if (body.containsKey("sla_minutes")) {
            input.setSla_minutes(asInt(body.get("sla_minutes")));
        }
        if (body.containsKey("cashier_write_back_enabled")) {
            Boolean v = asBool(body.get("cashier_write_back_enabled"));
            if (v != null) {
                input.setSync_legacy_rece(v ? 1 : 0);
            }
        }
        if (body.containsKey("sync_legacy_rece")) {
            input.setSync_legacy_rece(asInt(body.get("sync_legacy_rece")));
        }
        if (body.containsKey("serve_print_enabled")) {
            Boolean v = asBool(body.get("serve_print_enabled"));
            if (v != null) {
                input.setServe_print_enabled(v ? 1 : 0);
            }
        }
        if (body.containsKey("cross_order_merge")) {
            Boolean v = asBool(body.get("cross_order_merge"));
            if (v != null) {
                input.setMerge_same_dish(v ? 1 : 0);
            }
        }
        if (body.containsKey("merge_same_dish")) {
            input.setMerge_same_dish(asInt(body.get("merge_same_dish")));
        }
        if (body.containsKey("combo_independent")) {
            Boolean v = asBool(body.get("combo_independent"));
            if (v != null) {
                input.setCombo_merge(v ? 0 : 1);
            }
        }
        if (body.containsKey("combo_merge")) {
            input.setCombo_merge(asInt(body.get("combo_merge")));
        }
        if (body.containsKey("dine_pack_inline")) {
            Boolean v = asBool(body.get("dine_pack_inline"));
            if (v != null) {
                input.setPack_inline_merge(v ? 1 : 0);
            }
        }
        if (body.containsKey("pack_inline_merge")) {
            input.setPack_inline_merge(asInt(body.get("pack_inline_merge")));
        }
        if (body.containsKey("enable_prep_workflow")) {
            Boolean v = asBool(body.get("enable_prep_workflow"));
            if (v != null) {
                input.setEnable_prep_workflow(v ? 1 : 0);
            }
        } else if (body.containsKey("enablePrepWorkflow")) {
            Boolean v = asBool(body.get("enablePrepWorkflow"));
            if (v != null) {
                input.setEnable_prep_workflow(v ? 1 : 0);
            }
        } else if (body.containsKey("prep_enabled")) {
            Boolean v = asBool(body.get("prep_enabled"));
            if (v != null) {
                input.setEnable_prep_workflow(v ? 1 : 0);
            }
        }
        KdsShopConfig saved = configService.save(shopId, input);
        Map<String, Object> settingsView = toSettings(saved);
        eventPublisher.publishEvent(new KdsConfigChangedEvent(this, shopId, settingsView));
        return R.ok()
                .put("settings", settingsView);
    }

    private static Map<String, Object> toSettings(KdsShopConfig cfg) {
        Map<String, Object> m = new HashMap<>();
        m.put("shop_id", cfg.getShop_id());
        m.put("sla_minutes", cfg.getSla_minutes() != null ? cfg.getSla_minutes() : 10);
        int syncLegacyRece = cfg.getSync_legacy_rece() != null ? cfg.getSync_legacy_rece() : 1;
        int servePrint = cfg.getServe_print_enabled() != null ? cfg.getServe_print_enabled() : 1;
        int mergeSameDish = cfg.getMerge_same_dish() != null ? cfg.getMerge_same_dish() : 1;
        int comboMerge = cfg.getCombo_merge() != null ? cfg.getCombo_merge() : 1;
        int packInlineMerge = cfg.getPack_inline_merge() != null ? cfg.getPack_inline_merge() : 1;
        int enablePrep = cfg.getEnable_prep_workflow() != null ? cfg.getEnable_prep_workflow() : 1;
        m.put("cashier_write_back_enabled", syncLegacyRece != 0);
        m.put("serve_print_enabled", servePrint != 0);
        m.put("cross_order_merge", mergeSameDish != 0);
        m.put("add_dish_timeout_independent", true);
        m.put("combo_independent", comboMerge == 0);
        m.put("dine_pack_inline", packInlineMerge != 0);
        m.put("enable_prep_workflow", enablePrep != 0);
        m.put("enablePrepWorkflow", enablePrep != 0);
        m.put("prep_enabled", enablePrep != 0);
        m.put("sync_legacy_rece", syncLegacyRece);
        m.put("merge_same_dish", mergeSameDish);
        m.put("combo_merge", comboMerge);
        m.put("pack_inline_merge", packInlineMerge);
        return m;
    }

    private static Integer asInt(Object o) {
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o != null) {
            try {
                return Integer.parseInt(o.toString().trim());
            } catch (NumberFormatException ignore) {
                return null;
            }
        }
        return null;
    }

    private static Boolean asBool(Object o) {
        if (o instanceof Boolean) {
            return (Boolean) o;
        }
        if (o instanceof Number) {
            return ((Number) o).intValue() != 0;
        }
        if (o != null) {
            String s = o.toString().trim().toLowerCase();
            if ("true".equals(s) || "1".equals(s)) {
                return Boolean.TRUE;
            }
            if ("false".equals(s) || "0".equals(s)) {
                return Boolean.FALSE;
            }
        }
        return null;
    }
}
