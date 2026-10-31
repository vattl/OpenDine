package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsPairingTicketService;
import com.lanf.kds.util.KdsDeviceAuth;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping({"/kds/device", "/api/v1/kds/devices", "/api/v1/kds/device"})
public class KdsDeviceController {

    private static final String HEADER_DEVICE_TOKEN = "X-Kds-Device-Token";
    private static final String HEADER_SHOP_ID = "X-Shop-Id";

    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private KdsPairingTicketService pairingTicketService;
    @Autowired
    private com.lanf.kds.service.KdsConfigService configService;
    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private HttpServletRequest request;
    @Autowired(required = false)
    private SecurityAuditService securityAuditService;

    /** 查询当前令牌绑定的设备（用于核对 screen_tag 与门店） */
    @GetMapping({"/me", "/devices/me"})
    public R me() {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            KdsDevice enriched = deviceService.enrichScreens(deviceService.enrichWorkflows(device));
            return R.ok()
                    .put("device", enriched)
                    .put("data", enriched)
                    .put("protocol_version", 2);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        }
    }

    @PostMapping("/login")
    public R login(@RequestBody Map<String, Object> body) {
        try {
            String deviceCode = asText(body.get("deviceCode"), body.get("device_code"));
            if (deviceCode == null || deviceCode.trim().isEmpty()) {
                return R.error("device_code 不能为空");
            }
            Integer shopId = asInt(body.get("shopId"), body.get("shop_id"));
            String screenTag = asText(body.get("screenTag"), body.get("screen_tag"));
            String deviceName = asText(body.get("deviceName"), body.get("device_name"));
            String pairingCode = asText(body.get("pairingCode"), body.get("pairing_code"));
            String kdsPin = asText(body.get("kdsPin"), body.get("kds_pin"), body.get("pin"));

            String proxyShopHeader = request.getHeader(HEADER_SHOP_ID);
            if (StringUtils.hasText(proxyShopHeader)) {
                try {
                    int proxyShopId = Integer.parseInt(proxyShopHeader.trim());
                    if (shopId != null && shopId > 0 && !shopId.equals(proxyShopId)) {
                        return R.error(403, "设备不属于当前门店");
                    }
                    shopId = proxyShopId;
                } catch (NumberFormatException ignored) {}
            }

            KdsDevice existing = deviceService.findByDeviceCode(deviceCode.trim());
            if (existing != null) {
                if (shopId == null || shopId <= 0) {
                    shopId = existing.getShop_id();
                } else if (!shopId.equals(existing.getShop_id())) {
                    return R.error(403, "设备已绑定其他门店");
                }
                if (screenTag == null || screenTag.trim().isEmpty()) {
                    screenTag = existing.getScreen_tag();
                }
                if (deviceName == null || deviceName.trim().isEmpty()) {
                    deviceName = existing.getDevice_name();
                }
            }
            if (screenTag == null || screenTag.trim().isEmpty()) {
                screenTag = "workflow_board";
            }
            if (deviceName == null || deviceName.trim().isEmpty()) {
                deviceName = "后厨工作屏";
            }

            List<String> screenTags = parseScreenTags(body.get("screenTags"), body.get("screen_tags"));
            KdsDevice device;

            if (StringUtils.hasText(kdsPin)) {
                if (shopId == null || shopId <= 0) {
                    return R.error("请指定门店编号 (shopId)");
                }
                com.lanf.kds.entity.KdsShopConfig shopCfg = configService.getOrDefault(shopId);
                String expectedPin = shopCfg != null && shopCfg.getKds_pin() != null && !shopCfg.getKds_pin().trim().isEmpty()
                        ? shopCfg.getKds_pin().trim() : "123456";
                if (!expectedPin.equals(kdsPin.trim())) {
                    recordLoginDenied(shopId, "invalid_kds_pin");
                    return R.error(403, "KDS 登录 PIN 码错误");
                }
                try {
                    device = deviceService.bindOrLoginByPin(
                            shopId, deviceCode, deviceName, screenTag, screenTags);
                } catch (IllegalArgumentException ex) {
                    return R.error(403, ex.getMessage());
                }
            } else if (existing != null && hasValidCurrentToken(existing, request.getHeader(HEADER_DEVICE_TOKEN))) {
                if (!Integer.valueOf(1).equals(existing.getEnabled())) {
                    return R.error(403, "设备已被禁用，请在管理后台重新启用");
                }
                device = deviceService.loginBoundDevice(
                        shopId, deviceCode, deviceName, screenTag, screenTags, null);
            } else if (StringUtils.hasText(pairingCode)) {
                if (existing == null) {
                    recordLoginDenied(null, "unbound_kds_pairing_attempt");
                    return R.error(403, "设备未绑定或已禁用，请在管理后台绑定此设备编码");
                }
                if (!Integer.valueOf(1).equals(existing.getEnabled())) {
                    return R.error(403, "设备已被禁用，请在管理后台重新启用");
                }
                try {
                    device = pairingTicketService.consumeAndLogin(
                            pairingCode, deviceCode, deviceName, screenTag, screenTags);
                } catch (IllegalArgumentException invalidPairing) {
                    recordLoginDenied(existing.getShop_id(), "invalid_kds_pairing_ticket");
                    return R.error(403, invalidPairing.getMessage());
                }
            } else {
                recordLoginDenied(shopId, "unauthorized_kds_token_rotation");
                return R.error(403, "设备登录需要 6 位门店 PIN 码或有效设备 Token");
            }
            if (device == null) {
                return R.error(403, "设备登录失败，请核对门店信息");
            }
            List<String> workflows = parseWorkflows(body.get("workflows"));
            if (!workflows.isEmpty()) {
                deviceService.saveWorkflowSelection(device.getId(), workflows);
                device.setWorkflows(com.lanf.kds.KdsWorkflow.normalizeList(workflows));
            }
            KdsDevice enriched = deviceService.enrichWorkflows(device);
            return R.ok()
                    .put("device", enriched)
                    .put("data", enriched)
                    .put("protocol_version", 2);
        } catch (IllegalArgumentException invalid) {
            return R.error(400, invalid.getMessage());
        } catch (Exception unavailable) {
            return R.error(503, "设备登录服务暂不可用");
        }
    }

    @PostMapping("/heartbeat")
    public R heartbeat(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            deviceService.heartbeat(device.getDevice_code());
            Map<String, Object> data = new HashMap<>();
            data.put("shop_id", device.getShop_id());
            data.put("server_time_ms", System.currentTimeMillis());
            data.put("protocol_version", 2);
            return R.ok()
                    .put("data", data)
                    .put("protocol_version", 2);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        }
    }

    private void recordLoginDenied(Integer shopId, String reason) {
        if (securityAuditService != null) {
            securityAuditService.recordAccessDenied(
                    request, shopId, null, 403, reason, "kds:pair");
        }
    }

    private boolean hasValidCurrentToken(KdsDevice expected, String suppliedToken) {
        if (!StringUtils.hasText(suppliedToken)) {
            return false;
        }
        KdsDevice authenticated = deviceService.findByToken(suppliedToken.trim());
        return authenticated != null
                && expected.getId() != null
                && expected.getId().equals(authenticated.getId())
                && expected.getShop_id() != null
                && expected.getShop_id().equals(authenticated.getShop_id())
                && expected.getDevice_code() != null
                && expected.getDevice_code().equals(authenticated.getDevice_code());
    }

    private static Integer asInt(Object a, Object b) {
        Object o = a != null ? a : b;
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

    private static String asText(Object... candidates) {
        if (candidates == null) return null;
        for (Object o : candidates) {
            if (o != null) {
                String s = o.toString().trim();
                if (!s.isEmpty()) return s;
            }
        }
        return null;
    }

    private static List<String> parseScreenTags(Object... candidates) {
        List<String> out = new ArrayList<>();
        for (Object raw : candidates) {
            if (raw instanceof List) {
                for (Object o : (List<?>) raw) {
                    addScreenTag(out, o);
                }
            } else if (raw != null) {
                for (String part : raw.toString().split("[,;\\s]+")) {
                    addScreenTag(out, part);
                }
            }
        }
        return out;
    }

    private static void addScreenTag(List<String> out, Object raw) {
        if (raw == null) {
            return;
        }
        String s = raw.toString().trim();
        if (!s.isEmpty() && !out.contains(s)) {
            out.add(s);
        }
    }

    private static List<String> parseWorkflows(Object raw) {
        List<String> out = new ArrayList<>();
        if (raw instanceof List) {
            for (Object o : (List<?>) raw) {
                addWorkflow(out, o);
            }
        } else if (raw != null) {
            for (String part : raw.toString().split("[,;\\s]+")) {
                addWorkflow(out, part);
            }
        }
        return out;
    }

    private static void addWorkflow(List<String> out, Object raw) {
        if (raw == null) {
            return;
        }
        String s = raw.toString().trim().toLowerCase();
        if (Arrays.asList("prep", "cook", "serve").contains(s) && !out.contains(s)) {
            out.add(s);
        }
    }
}
