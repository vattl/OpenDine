package com.lanf.kds.controller.admin;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsDishScreen;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsStation;
import com.lanf.entity.Order;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsPairingTicketService;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.kds.service.KdsServePrintService;
import com.lanf.kds.service.KdsStationService;
import com.lanf.service.IOrderService;
import com.lanf.service.CashierClientRequestService;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.kds.event.KdsConfigChangedEvent;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * KDS 运维配置（B 端）。
 */
@RestController
@RequestMapping("/admin/kds")
public class AdminKdsController {

    @Autowired
    private KdsStationService stationService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private KdsPairingTicketService pairingTicketService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsOrderHook kdsOrderHook;
    @Autowired
    private KdsServePrintService servePrintService;
    @Autowired
    private CashierClientRequestService clientRequestService;
    @Autowired(required = false)
    private ApplicationEventPublisher eventPublisher;

    private Integer requireShopId() {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId == null || shopId <= 0) {
            throw new IllegalStateException("缺少门店上下文，请传 X-Shop-Id");
        }
        return shopId;
    }

    private R shopError(Exception e) {
        if (e instanceof IllegalStateException) {
            return R.error(4001, e.getMessage());
        }
        return R.error(e.getMessage());
    }

    @GetMapping("/station/list")
    public R stationList() {
        try {
            int shopId = requireShopId();
            return R.ok().put("list", stationService.listByShop(shopId));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/station/save")
    public R stationSave(@RequestBody KdsStation station) {
        try {
            int shopId = requireShopId();
            return R.ok().put("station", stationService.save(shopId, station));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @GetMapping("/station/delete")
    public R stationDelete(@RequestParam Long id) {
        try {
            int shopId = requireShopId();
            if (id == null) {
                return R.error("id 不能为空");
            }
            stationService.delete(shopId, id);
            return R.ok();
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/station/init-five")
    public R stationInitFive() {
        try {
            int shopId = requireShopId();
            return R.ok().put("list", stationService.initFiveScreens(shopId));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/station/category/bind")
    public R categoryBind(@RequestBody Map<String, Object> body) {
        try {
            int shopId = requireShopId();
            Long stationId = asLong(body.get("stationId"));
            if (stationId == null) {
                stationId = asLong(body.get("station_id"));
            }
            if (stationId == null) {
                return R.error("stationId 不能为空");
            }
            List<String> cidList = asStringList(body.get("cidList"));
            if (cidList.isEmpty()) {
                cidList = asStringList(body.get("cid_list"));
            }
            stationService.bindCategories(stationId, shopId, cidList);
            return R.ok().put("categories", stationService.listCategories(stationId, shopId));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @GetMapping("/station/category/list")
    public R categoryList(@RequestParam Long stationId) {
        try {
            int shopId = requireShopId();
            if (stationId == null) {
                return R.error("stationId 不能为空");
            }
            return R.ok().put("categories", stationService.listCategories(stationId, shopId));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/dish-screen/bind")
    public R dishScreenBind(@RequestBody Map<String, Object> body) {
        try {
            int shopId = requireShopId();
            String screenTag = asText(body.get("screenTag"), body.get("screen_tag"));
            if (screenTag == null) {
                return R.error("screen_tag 不能为空");
            }
            List<Integer> dishIds = asIntList(body.get("dishIds"));
            if (dishIds.isEmpty()) {
                dishIds = asIntList(body.get("dish_ids"));
            }
            stationService.bindDishScreens(shopId, screenTag, dishIds);
            return R.ok().put("list", stationService.listDishScreens(shopId, null, screenTag));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @GetMapping("/dish-screen/list")
    public R dishScreenList(@RequestParam(required = false) Integer dishId,
                            @RequestParam(required = false) String screenTag) {
        try {
            int shopId = requireShopId();
            List<KdsDishScreen> list = stationService.listDishScreens(shopId, dishId, screenTag);
            return R.ok().put("list", list);
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @GetMapping("/config/get")
    public R configGet() {
        try {
            int shopId = requireShopId();
            return R.ok().put("config", configService.getOrDefault(shopId));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/config/save")
    public R configSave(@RequestBody KdsShopConfig config) {
        try {
            int shopId = requireShopId();
            KdsShopConfig saved = configService.save(shopId, config);
            if (eventPublisher != null) {
                Map<String, Object> settingsView = new java.util.HashMap<>();
                settingsView.put("shop_id", shopId);
                settingsView.put("enable_prep_workflow", saved.getEnable_prep_workflow() != null && saved.getEnable_prep_workflow() != 0);
                settingsView.put("enablePrepWorkflow", saved.getEnable_prep_workflow() != null && saved.getEnable_prep_workflow() != 0);
                settingsView.put("prep_enabled", saved.getEnable_prep_workflow() != null && saved.getEnable_prep_workflow() != 0);
                settingsView.put("config", saved);
                eventPublisher.publishEvent(new KdsConfigChangedEvent(this, shopId, settingsView));
            }
            return R.ok().put("config", saved);
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @GetMapping("/device/list")
    public R deviceList() {
        try {
            int shopId = requireShopId();
            List<Map<String, Object>> views = new java.util.ArrayList<>();
            for (KdsDevice device : deviceService.listByShop(shopId)) {
                views.add(toDeviceManagementView(device));
            }
            return R.ok().put("list", views);
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/device/bind")
    public R deviceBind(@RequestBody Map<String, Object> body) {
        try {
            int shopId = requireShopId();
            String deviceCode = asText(body.get("deviceCode"), body.get("device_code"));
            String deviceName = asText(body.get("deviceName"), body.get("device_name"));
            String screenTag = asText(body.get("screenTag"), body.get("screen_tag"));
            if (deviceCode == null) {
                return R.error("device_code 不能为空");
            }
            if (screenTag == null) {
                return R.error("screen_tag 不能为空");
            }
            List<String> screenTags = asStringList(body.get("screenTags"));
            if (screenTags.isEmpty()) {
                screenTags = asStringList(body.get("screen_tags"));
            }
            // Token 只能由云端 KdsDeviceService 签发或复用。管理端/收银端
            // 提交的 deviceToken 不是可信身份，不得写入鉴权字段。
            KdsDevice device = deviceService.bindMetadata(shopId, deviceCode, deviceName, screenTag, screenTags);
            List<String> workflows = asStringList(body.get("workflows"));
            if (workflows.isEmpty()) {
                workflows = asStringList(body.get("workflows_json"));
            }
            if (!workflows.isEmpty()) {
                deviceService.saveWorkflowSelection(device.getId(), workflows);
                device.setWorkflows(com.lanf.kds.KdsWorkflow.normalizeList(workflows));
            }
            return R.ok().put("device", toDeviceManagementView(deviceService.enrichWorkflows(device)));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    @PostMapping("/device/proxy-login")
    public R deviceProxyLogin(@RequestBody Map<String, Object> body) {
        return R.error(410, "代理登录已停用；请原样转发 /kds/device/login");
    }

    /** Issues a short-lived code for a pre-bound device; plaintext is returned exactly once. */
    @PostMapping("/device/pairing-ticket")
    public R devicePairingTicket(@RequestBody Map<String, Object> body) {
        try {
            int shopId = requireShopId();
            String deviceCode = asText(body.get("deviceCode"), body.get("device_code"));
            if (deviceCode == null) {
                return R.error("device_code 不能为空");
            }
            Object rawAdminId = httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            String createdBy = rawAdminId == null ? null : "admin:" + rawAdminId;
            KdsPairingTicketService.PairingTicket ticket =
                    pairingTicketService.issue(shopId, deviceCode, createdBy);
            Map<String, Object> data = new java.util.LinkedHashMap<>();
            data.put("device_code", ticket.getDeviceCode());
            data.put("pairing_code", ticket.getPairingCode());
            data.put("expires_at_ms", ticket.getExpiresAtMs());
            return R.ok().put("data", data);
        } catch (IllegalArgumentException rejected) {
            return R.error(4030, rejected.getMessage());
        } catch (Exception e) {
            return shopError(e);
        }
    }

    /** Management responses expose device metadata only; credentials leave the cloud solely on login. */
    private Map<String, Object> toDeviceManagementView(KdsDevice device) {
        Map<String, Object> view = new java.util.LinkedHashMap<>();
        view.put("id", device.getId());
        view.put("shop_id", device.getShop_id());
        view.put("station_id", device.getStation_id());
        view.put("screen_tag", device.getScreen_tag());
        view.put("device_code", device.getDevice_code());
        view.put("device_name", device.getDevice_name());
        view.put("workflows_json", device.getWorkflows_json());
        view.put("workflows", device.getWorkflows());
        view.put("screen_tags", device.getScreen_tags());
        view.put("last_heartbeat_at", device.getLast_heartbeat_at());
        view.put("token_expires_at", device.getToken_expires_at());
        view.put("token_revoked_at", device.getToken_revoked_at());
        view.put("enabled", device.getEnabled());
        view.put("created_at", device.getCreated_at());
        view.put("updated_at", device.getUpdated_at());
        return view;
    }

    /**
     * Retired: a cashier administrator session must never synthesize a KDS
     * actor or authorize a queued device command. The LAN proxy forwards the
     * original device token directly to /kds/v2/commands instead.
     */
    @PostMapping("/device/proxy-command")
    public R deviceProxyCommand(@RequestBody Map<String, Object> body) {
        return R.error(410, "收银代理命令授权已停用；请原样转发 /kds/v2/commands");
    }

    @PostMapping("/ticket/repush")
    public R ticketRepush(@RequestBody Map<String, Object> body) {
        try {
            int shopId = requireShopId();
            Integer orderId = asInt(body.get("orderId"), body.get("order_id"));
            if (orderId == null) {
                return R.error("order_id 不能为空");
            }
            Order order = orderService.getById(orderId);
            if (order == null || order.getShop_id() == null || !order.getShop_id().equals(shopId)) {
                return R.error("订单不存在或不属于当前门店");
            }
            kdsOrderHook.afterOrderCommitted(order, null, KdsOrderHook.Trigger.MANUAL);
            return R.ok();
        } catch (Exception e) {
            return shopError(e);
        }
    }

    /**
     * 传菜单手动打印/补打接口（B 端/收银端调用）
     */
    @PostMapping("/ticket/print-serve")
    public R printServeTicket(@RequestBody(required = false) Map<String, Object> body) {
        try {
            int shopId = requireShopId();
            String requestId = httpServletRequest.getHeader("X-Client-Request-Id");
            Object rawAdminId = httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            Integer adminId = rawAdminId instanceof Integer ? (Integer) rawAdminId : null;
            return clientRequestService.execute(shopId, adminId, requestId,
                    "/admin/kds/ticket/print-serve", body, () -> printServeTicketInternal(shopId, body));
        } catch (Exception e) {
            return shopError(e);
        }
    }

    private R printServeTicketInternal(int shopId, Map<String, Object> body) {
        Integer detailId = asInt(body != null ? body.get("detail_id") : null, body != null ? body.get("detailId") : null, body != null ? body.get("item_id") : null, body != null ? body.get("itemId") : null);
        Integer orderId = asInt(body != null ? body.get("order_id") : null, body != null ? body.get("orderId") : null);
        Integer quantity = asInt(body != null ? body.get("quantity") : null, body != null ? body.get("qty") : null);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> lines = body != null && body.get("lines") instanceof List
                ? (List<Map<String, Object>>) body.get("lines") : null;
        Map<String, Object> data = servePrintService.printManual(shopId, orderId, detailId, quantity, lines);
        return R.ok().put("data", data);
    }

    @RequestMapping(value = {"/device/unbind", "/device/delete"}, method = {RequestMethod.POST, RequestMethod.GET, RequestMethod.DELETE})
    public R deviceUnbind(
            @RequestBody(required = false) Map<String, Object> body,
            @RequestParam(value = "id", required = false) Long paramId,
            @RequestParam(value = "deviceId", required = false) Long paramDeviceId,
            @RequestParam(value = "device_id", required = false) Long paramDeviceIdSnake,
            @RequestParam(value = "deviceCode", required = false) String paramDeviceCode,
            @RequestParam(value = "device_code", required = false) String paramDeviceCodeSnake) {
        try {
            int shopId = requireShopId();
            Long id = asLong(paramId, paramDeviceId, paramDeviceIdSnake,
                    body != null ? body.get("id") : null,
                    body != null ? body.get("deviceId") : null,
                    body != null ? body.get("device_id") : null);
            String deviceCode = asText(paramDeviceCode, paramDeviceCodeSnake,
                    body != null ? body.get("deviceCode") : null,
                    body != null ? body.get("device_code") : null);
            if (id == null && (deviceCode == null || deviceCode.trim().isEmpty())) {
                return R.error("device_code 或 id 不能为空");
            }
            if (id != null) {
                deviceService.deleteDeviceById(shopId, id);
            } else {
                deviceService.deleteDevice(shopId, deviceCode);
            }
            return R.ok();
        } catch (Exception e) {
            return shopError(e);
        }
    }

    private static Integer asInt(Object... candidates) {
        for (Object o : candidates) {
            if (o instanceof Number) {
                return ((Number) o).intValue();
            }
            if (o != null) {
                try {
                    return Integer.parseInt(o.toString().trim());
                } catch (NumberFormatException ignored) {}
            }
        }
        return null;
    }

    private static Long asLong(Object... candidates) {
        for (Object o : candidates) {
            if (o instanceof Number) {
                return ((Number) o).longValue();
            }
            if (o != null) {
                try {
                    return Long.parseLong(o.toString().trim());
                } catch (NumberFormatException ignored) {}
            }
        }
        return null;
    }

    private static String asText(Object... candidates) {
        for (Object o : candidates) {
            if (o != null) {
                String s = o.toString().trim();
                if (!s.isEmpty()) {
                    return s;
                }
            }
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    private static List<String> asStringList(Object raw) {
        List<String> out = new ArrayList<>();
        if (raw instanceof List) {
            for (Object o : (List<?>) raw) {
                if (o != null && !o.toString().trim().isEmpty()) {
                    out.add(o.toString().trim());
                }
            }
        }
        return out;
    }

    @SuppressWarnings("unchecked")
    private static List<Integer> asIntList(Object raw) {
        List<Integer> out = new ArrayList<>();
        if (raw instanceof List) {
            for (Object o : (List<?>) raw) {
                if (o instanceof Number) {
                    out.add(((Number) o).intValue());
                } else if (o != null) {
                    try {
                        out.add(Integer.parseInt(o.toString().trim()));
                    } catch (NumberFormatException ignore) {
                        // skip
                    }
                }
            }
        }
        return out;
    }
}
