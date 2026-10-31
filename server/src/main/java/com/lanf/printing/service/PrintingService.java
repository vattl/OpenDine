package com.lanf.printing.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.common.PageResult;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.entity.PrintingJob;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.entity.PrintingTemplate;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.mapper.PrintingTemplateMapper;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.PrintTemplateDsl;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import com.lanf.entity.Shop;
import com.lanf.printing.engine.PrintTemplateEngine;
import com.lanf.printing.engine.PrintTemplateOptions;
import com.lanf.printing.engine.PrintTicketParser;
import com.lanf.printing.model.PrintPreviewResult;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintResolvedPreview;
import com.lanf.service.IFeieyunService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShiftService;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import javax.annotation.PostConstruct;

import java.io.IOException;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 打印模块服务：设备、规则、任务（协调文档 §2 打印相关行）。
 * 约束（docs/_settings_api_dev_spec.md §5）：
 * - 设备与规则带 version 乐观锁，冲突返回 409 + PRINTING_VERSION_CONFLICT + 最新摘要；
 * - connection_json 中密钥/序列号读取时脱敏（key → ****，sn → **** + 尾 4 位）；
 * - 打印测试：CLOUD 设备真实调用既有飞鹅打印服务 {@link IFeieyunService#print(Integer, String, String, int)}；
 *   LAN/USB/BLUETOOTH 设备任务置 PENDING_DEVICE、executor=DEVICE，由端侧执行；
 * - 小票模板：完全基于数据库 t_printing_template 中的 JSON DSL 解释渲染。
 */
@Service
public class PrintingService {

    private static final Logger log = LoggerFactory.getLogger(PrintingService.class);

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;
    private static final DateTimeFormatter DATETIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public static final String TRANSPORT_LAN = "LAN";
    public static final String TRANSPORT_USB = "USB";
    public static final String TRANSPORT_BLUETOOTH = "BLUETOOTH";
    public static final String TRANSPORT_CLOUD = "CLOUD";

    public static final String STATUS_PENDING_DEVICE = "PENDING_DEVICE";
    public static final String STATUS_SENT = "SENT";
    public static final String STATUS_PRINTED = "PRINTED";
    public static final String STATUS_FAILED = "FAILED";
    public static final String STATUS_CANCELED = "CANCELED";

    /** 云端打印服务未就绪时的稳定错误文案 */
    public static final String CLOUD_NOT_CONFIGURED = "cloud printer service not configured";

    private static final Set<String> TRANSPORTS = new HashSet<>(
            Arrays.asList(TRANSPORT_LAN, TRANSPORT_USB, TRANSPORT_BLUETOOTH, TRANSPORT_CLOUD));
    private static final Set<String> DEVICE_STATUSES = new HashSet<>(
            Arrays.asList("ONLINE", "OFFLINE", "ERROR", "UNKNOWN"));
    private static final Set<String> JOB_STATUSES = new HashSet<>(
            Arrays.asList(STATUS_PENDING_DEVICE, STATUS_SENT, STATUS_PRINTED, STATUS_FAILED, STATUS_CANCELED));
    public static final Set<String> ALLOWED_TICKET_TYPES = new HashSet<>(
            Arrays.asList("KITCHEN", "FULL_ORDER", "PRE_CHECKOUT", "CHECKOUT", "EXPEDITE", "TAKEOUT", "SHIFT", "REFUND", "LABEL", "TEST"));

    private static final int MAX_PAGE_SIZE = 100;

    @Autowired
    private PrintingDeviceMapper deviceMapper;
    @Autowired
    private PrintingRuleMapper ruleMapper;
    @Autowired
    private PrintingJobMapper jobMapper;
    @Autowired(required = false)
    private PrintingTemplateMapper templateMapper;
    /** 既有飞鹅云打印服务（FeieyunController 背后的同一实现）；仅 CLOUD 设备使用 */
    @Autowired
    private IFeieyunService feieyunService;
    @Autowired
    private com.lanf.service.IShopService shopService;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired(required = false)
    private PrintTemplateEngine printTemplateEngine;
    @Autowired(required = false)
    private IOrderService orderService;
    @Autowired(required = false)
    private IOrderDetailService orderDetailService;
    @Autowired(required = false)
    private IShiftService shiftService;
    @Autowired(required = false)
    private PrintDispatcherService printDispatcherService;

    @PostConstruct
    public void initDefaultSystemTemplates() {
        if (templateMapper == null || printTemplateEngine == null) {
            return;
        }
        try {
            String[] scenarios = new String[] {
                    "KITCHEN", "FULL_ORDER", "PRE_CHECKOUT", "CHECKOUT", "EXPEDITE", "TAKEOUT", "PACKING", "SHIFT", "REFUND", "LABEL", "TEST"
            };
            for (String scenario : scenarios) {
                Integer count = templateMapper.selectCount(new QueryWrapper<PrintingTemplate>()
                        .eq("shop_id", 0)
                        .eq("scenario", scenario));
                if (count == null || count == 0) {
                    PrintTemplateDsl dsl = printTemplateEngine.buildDefaultDsl(scenario, "58mm");
                    String json = objectMapper.writeValueAsString(dsl);
                    PrintingTemplate pt = new PrintingTemplate();
                    pt.setShop_id(0);
                    pt.setTemplate_code("tpl_sys_" + scenario.toLowerCase());
                    pt.setTemplate_name("系统默认" + PrintScenario.getScenarioDisplayName(scenario));
                    pt.setScenario(scenario);
                    pt.setPaper_size("58mm");
                    pt.setIs_system(1);
                    pt.setIs_default(1);
                    pt.setTemplate_json(json);
                    pt.setVersion(1);
                    pt.setCreated_at(LocalDateTime.now(ZONE));
                    pt.setUpdated_at(pt.getCreated_at());
                    templateMapper.insert(pt);
                    log.info("[printing] Auto-initialized system printing template for scenario: {}", scenario);
                }
            }
        } catch (Exception e) {
            log.warn("[printing] initDefaultSystemTemplates check/seed failed: {}", e.getMessage());
        }
    }

    // ---------------- 设备 ----------------

    /** 设备列表：transport/status 筛选 + 分页；connection 脱敏后返回 */
    public PageResult listDevices(int shopId, String transport, String status, int page, int pageSize) {
        int[] pp = normalizePage(page, pageSize);
        QueryWrapper<PrintingDevice> qw = new QueryWrapper<>();
        qw.eq("shop_id", shopId);
        if (!StringUtil.isEmpty(transport)) {
            String t = transport.trim().toUpperCase();
            if (!TRANSPORTS.contains(t)) {
                throw new ApiException(400, "PRINTING_TRANSPORT_INVALID", "transport 仅支持 LAN/USB/BLUETOOTH/CLOUD");
            }
            qw.eq("transport", t);
        }
        if (!StringUtil.isEmpty(status)) {
            String s = status.trim().toUpperCase();
            if (!DEVICE_STATUSES.contains(s)) {
                throw new ApiException(400, "PRINTING_STATUS_INVALID", "status 仅支持 ONLINE/OFFLINE/ERROR/UNKNOWN");
            }
            qw.eq("status", s);
        }
        qw.orderByDesc("updated_at").orderByDesc("id");
        Page<PrintingDevice> result = deviceMapper.selectPage(new Page<>(pp[0], pp[1]), qw);
        List<Map<String, Object>> items = new ArrayList<>();
        if (result.getRecords() != null) {
            for (PrintingDevice d : result.getRecords()) {
                items.add(deviceSummary(d));
            }
        }
        return PageResult.of(pp[0], pp[1], result.getTotal(), items);
    }

    /** 获取设备详情 */
    public Map<String, Object> getDeviceDetail(int shopId, long deviceId) {
        PrintingDevice device = requireDevice(shopId, deviceId);
        return deviceSummary(device);
    }

    /** 新建设备：校验 transport/status，SN 唯一性校验，version=1 起步；返回脱敏摘要 */
    public Map<String, Object> createDevice(int shopId, Map<String, Object> body, Integer adminId) {
        if (body == null || body.isEmpty()) {
            throw new ApiException(400, "PRINTING_PAYLOAD_EMPTY", "请求体不能为空");
        }
        String name = requireString(body.get("name"), "PRINTING_NAME_REQUIRED", "设备名称不能为空");
        if (name.length() > 128) {
            throw new ApiException(400, "PRINTING_NAME_TOO_LONG", "设备名称不能超过 128 字符");
        }

        // 门店下名称唯一性校验
        int nameCount = deviceMapper.selectCount(new QueryWrapper<PrintingDevice>()
                .eq("shop_id", shopId).eq("name", name));
        if (nameCount > 0) {
            throw new ApiException(400, "PRINTING_NAME_DUPLICATE", "门店下已存在同名打印设备：" + name);
        }

        String transport = requireTransport(body.get("transport"));
        String status = optionalStatus(body.get("status"));
        String brand = body.containsKey("vendor") && body.get("vendor") != null
                ? body.get("vendor").toString().trim()
                : optionalString(body.get("brand"), 64, "PRINTING_BRAND_TOO_LONG", "品牌/型号不能超过 64 字符");

        Map<String, Object> connection = parseConnection(body.get("connection"));
        // 允许直接在顶层传递连接配置字段
        mergeFlatConnectionFields(body, connection);

        // 云打印必填项校验
        if (TRANSPORT_CLOUD.equals(transport)) {
            if (connection.get("sn") == null || String.valueOf(connection.get("sn")).trim().isEmpty()) {
                throw new ApiException(400, "PRINTING_SN_REQUIRED", "云打印模式下设备 SN 码不能为空");
            }
        } else if (TRANSPORT_LAN.equals(transport)) {
            if (connection.get("ip") == null || String.valueOf(connection.get("ip")).trim().isEmpty()) {
                throw new ApiException(400, "PRINTING_IP_REQUIRED", "局域网 LAN 模式下设备 IP 地址不能为空");
            }
        }

        // SN 唯一性校验
        if (connection.containsKey("sn") && connection.get("sn") != null) {
            String sn = String.valueOf(connection.get("sn")).trim();
            if (!sn.isEmpty()) {
                checkSnUniqueness(shopId, null, sn);
            }
        }

        PrintingDevice device = new PrintingDevice();
        device.setShop_id(shopId);
        device.setName(name);
        device.setTransport(transport);
        device.setBrand(brand);
        device.setConnection_json(json(connection));
        device.setStatus(status);
        device.setVersion(1);
        device.setCreated_at(LocalDateTime.now(ZONE));
        device.setUpdated_at(device.getCreated_at());
        deviceMapper.insert(device);
        log.info("[printing] device created: shop_id={}, id={}, transport={}, admin={}",
                shopId, device.getId(), transport, adminId);

        // 云打印机自动尝试同步至飞鹅云开放平台
        if (TRANSPORT_CLOUD.equals(transport) && feieyunService != null) {
            String sn = connection.get("sn") != null ? String.valueOf(connection.get("sn")).trim() : "";
            String key = connection.get("key") != null ? String.valueOf(connection.get("key")).trim() : (connection.get("ukey") != null ? String.valueOf(connection.get("ukey")).trim() : "");
            String user = connection.get("user") != null ? String.valueOf(connection.get("user")).trim() : "";
            String ukey = connection.get("ukey") != null ? String.valueOf(connection.get("ukey")).trim() : "";
            String apiUrl = connection.get("apiUrl") != null ? String.valueOf(connection.get("apiUrl")).trim() : (connection.get("url") != null ? String.valueOf(connection.get("url")).trim() : null);
            if (!sn.isEmpty() && !key.isEmpty() && !key.contains("*")) {
                try {
                    String printerItem = sn + "#" + key + "#" + name;
                    if (!user.isEmpty() && !ukey.isEmpty() && !StringUtil.isEmpty(apiUrl)) {
                        feieyunService.addPrinterWithCredential(apiUrl, user, ukey, printerItem);
                        log.info("[printing] feieyun cloud printer bound: sn={}", sn);
                    } else {
                        log.warn("[printing] feieyun cloud printer auto-bind skipped: 设备未配置飞鹅云凭据(url/user/ukey), sn={}", sn);
                    }
                } catch (Exception e) {
                    log.warn("[printing] feieyun cloud printer auto-bind failed: sn={}, error={}", sn, e.getMessage());
                }
            }
        }

        return deviceSummary(device);
    }

    /** 更新设备：version 乐观锁（WHERE version=?），冲突 409 + 最新摘要；掩码密钥保留 */
    public Map<String, Object> updateDevice(int shopId, long deviceId, Map<String, Object> body, Integer adminId) {
        if (body == null || body.isEmpty()) {
            throw new ApiException(400, "PRINTING_PAYLOAD_EMPTY", "请求体不能为空");
        }
        PrintingDevice existing = requireDevice(shopId, deviceId);
        Integer expectedVersion = requireVersion(body.get("version"));

        PrintingDevice patch = new PrintingDevice();
        boolean changed = false;
        if (body.containsKey("name")) {
            String name = requireString(body.get("name"), "PRINTING_NAME_REQUIRED", "设备名称不能为空");
            if (name.length() > 128) {
                throw new ApiException(400, "PRINTING_NAME_TOO_LONG", "设备名称不能超过 128 字符");
            }
            if (!name.equals(existing.getName())) {
                int nameCount = deviceMapper.selectCount(new QueryWrapper<PrintingDevice>()
                        .eq("shop_id", shopId).eq("name", name).ne("id", deviceId));
                if (nameCount > 0) {
                    throw new ApiException(400, "PRINTING_NAME_DUPLICATE", "门店下已存在同名打印设备：" + name);
                }
            }
            patch.setName(name);
            changed = true;
        }
        if (body.containsKey("transport")) {
            patch.setTransport(requireTransport(body.get("transport")));
            changed = true;
        }
        if (body.containsKey("brand") || body.containsKey("vendor")) {
            String brand = body.containsKey("vendor") && body.get("vendor") != null
                    ? body.get("vendor").toString().trim()
                    : optionalString(body.get("brand"), 64, "PRINTING_BRAND_TOO_LONG", "品牌/型号不能超过 64 字符");
            patch.setBrand(brand);
            changed = true;
        }
        if (body.containsKey("status")) {
            patch.setStatus(optionalStatus(body.get("status")));
            changed = true;
        }

        // 解析并合并连接配置
        Map<String, Object> existingConn = parseConnection(existing.getConnection_json());
        Map<String, Object> newConn = new LinkedHashMap<>(existingConn);

        boolean connModified = body.containsKey("connection");
        if (body.containsKey("connection")) {
            Map<String, Object> incomingConn = parseConnection(body.get("connection"));
            mergePreservingSecrets(newConn, incomingConn);
        }
        if (mergeFlatConnectionFields(body, newConn)) {
            connModified = true;
        }

        if (connModified) {
            // SN 唯一性校验
            if (newConn.containsKey("sn") && newConn.get("sn") != null) {
                String sn = String.valueOf(newConn.get("sn")).trim();
                if (!sn.isEmpty()) {
                    checkSnUniqueness(shopId, deviceId, sn);
                }
            }
            patch.setConnection_json(json(newConn));
            changed = true;
        }

        if (!changed) {
            throw new ApiException(400, "PRINTING_NO_UPDATABLE_FIELDS",
                    "请求未包含可更新字段（name/transport/brand/vendor/status/connection）");
        }
        patch.setVersion(expectedVersion + 1);
        patch.setUpdated_at(LocalDateTime.now(ZONE));

        int updated = deviceMapper.update(patch, new QueryWrapper<PrintingDevice>()
                .eq("id", deviceId).eq("shop_id", shopId).eq("version", expectedVersion));
        if (updated == 0) {
            throw deviceVersionConflict(existing);
        }
        log.info("[printing] device updated: shop_id={}, id={}, version={}->{}, admin={}",
                shopId, deviceId, expectedVersion, expectedVersion + 1, adminId);
        return deviceSummary(requireDevice(shopId, deviceId));
    }

    /** 删除设备：校验是否被打印规则引用 */
    public void deleteDevice(int shopId, long deviceId) {
        PrintingDevice existing = requireDevice(shopId, deviceId);
        List<PrintingRule> referencingRules = ruleMapper.selectList(new QueryWrapper<PrintingRule>()
                .eq("shop_id", shopId)
                .eq("device_id", deviceId)
                .eq("enabled", 1));

        if (referencingRules != null && !referencingRules.isEmpty()) {
            List<String> rules = new ArrayList<>();
            for (PrintingRule r : referencingRules) {
                rules.add(r.getScenario());
            }
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("deviceId", deviceId);
            data.put("deviceName", existing.getName());
            data.put("rules", rules);
            data.put("ruleCount", rules.size());
            throw new ApiException(400, "PRINT_DEVICE_IN_USE_BY_RULE",
                    "待删除打印机正被生效中的出票规则引用，无法删除", data);
        }

        // 云打印机在删除时尝试从飞鹅开放平台解绑
        if (TRANSPORT_CLOUD.equalsIgnoreCase(existing.getTransport()) && feieyunService != null) {
            String sn = connectionSn(existing);
            if (!StringUtil.isEmpty(sn)) {
                try {
                    Map<String, Object> conn = parseConnection(existing.getConnection_json());
                    String user = conn.get("user") != null ? String.valueOf(conn.get("user")).trim() : "";
                    String ukey = conn.get("ukey") != null ? String.valueOf(conn.get("ukey")).trim() : "";
                    String apiUrl = conn.get("apiUrl") != null ? String.valueOf(conn.get("apiUrl")).trim() : (conn.get("url") != null ? String.valueOf(conn.get("url")).trim() : null);
                    if (!user.isEmpty() && !ukey.isEmpty() && !StringUtil.isEmpty(apiUrl)) {
                        feieyunService.deletePrinterWithCredential(apiUrl, user, ukey, sn);
                        log.info("[printing] feieyun cloud printer deleted: sn={}", sn);
                    } else {
                        log.warn("[printing] feieyun cloud printer auto-delete skipped: 设备未配置飞鹅云凭据(url/user/ukey), sn={}", sn);
                    }
                } catch (Exception e) {
                    log.warn("[printing] feieyun cloud printer auto-delete failed: sn={}, error={}", sn, e.getMessage());
                }
            }
        }

        deviceMapper.deleteById(deviceId);
        log.info("[printing] device deleted: shop_id={}, id={}", shopId, deviceId);
    }

    /** 设备实时状态探活 */
    public Map<String, Object> probeDeviceStatus(int shopId, long deviceId) {
        PrintingDevice device = requireDevice(shopId, deviceId);
        boolean online = "ONLINE".equalsIgnoreCase(device.getStatus());
        String status = device.getStatus() != null ? device.getStatus().toUpperCase() : "ONLINE";
        String paperStatus = "NORMAL";
        String coverStatus = "CLOSED";

        if (TRANSPORT_CLOUD.equalsIgnoreCase(device.getTransport())) {
            String sn = connectionSn(device);
            if (feieyunService != null && !StringUtil.isEmpty(sn)) {
                try {
                    Map<String, Object> conn = parseConnection(device.getConnection_json());
                    String user = conn.get("user") != null ? String.valueOf(conn.get("user")).trim() : null;
                    String ukey = conn.get("ukey") != null ? String.valueOf(conn.get("ukey")).trim() : null;
                    String apiUrl = conn.get("url") != null ? String.valueOf(conn.get("url")).trim() : null;
                    if (StringUtil.isEmpty(apiUrl) && conn.get("apiUrl") != null) {
                        apiUrl = String.valueOf(conn.get("apiUrl")).trim();
                    }

                    String res = null;
                    if (!StringUtil.isEmpty(user) && !StringUtil.isEmpty(ukey) && !StringUtil.isEmpty(apiUrl)) {
                        res = feieyunService.queryPrinterStatusWithCredential(apiUrl, user, ukey, sn);
                    } else {
                        log.warn("[printing] probe status skipped: 设备未配置飞鹅云凭据(url/user/ukey), sn={}, 保持 DB 状态", sn);
                    }

                    if (res != null) {
                        Map<String, Object> parsed = parseFeieyunPrinterStatus(res);
                        online = Boolean.TRUE.equals(parsed.get("online"));
                        status = (String) parsed.get("status");
                        paperStatus = (String) parsed.get("paperStatus");
                        coverStatus = (String) parsed.get("coverStatus");

                        // 状态发生变化时同步刷新 DB
                        if (!status.equalsIgnoreCase(device.getStatus())) {
                            PrintingDevice updateDev = new PrintingDevice();
                            updateDev.setId(deviceId);
                            updateDev.setStatus(status);
                            updateDev.setUpdated_at(LocalDateTime.now(ZONE));
                            deviceMapper.updateById(updateDev);
                            device.setStatus(status);
                        }
                    }
                } catch (Exception e) {
                    log.warn("[printing] probe cloud printer status error: sn={}, error={}", sn, e.getMessage());
                }
            }
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("deviceId", deviceId);
        out.put("online", online);
        out.put("status", status);
        out.put("paperStatus", paperStatus);
        out.put("coverStatus", coverStatus);
        out.put("lastPingTime", iso(LocalDateTime.now(ZONE)));
        return out;
    }

    /**
     * 解析飞鹅云原生状态：
     * 0: 离线
     * 1: 在线，工作状态正常
     * 2: 在线，工作状态不正常
     */
    public static Map<String, Object> parseFeieyunPrinterStatus(String rawResponse) {
        Map<String, Object> res = new LinkedHashMap<>();
        boolean online = true;
        String status = "ONLINE";
        String paperStatus = "NORMAL";
        String coverStatus = "CLOSED";

        if (!StringUtil.isEmpty(rawResponse)) {
            String dataText = rawResponse.trim();
            try {
                JsonNode root = new ObjectMapper().readTree(rawResponse);
                if (root != null && root.has("data") && !root.get("data").isNull()) {
                    dataText = root.get("data").asText().trim();
                }
            } catch (Exception ignored) {}

            if ("0".equals(dataText) || dataText.contains("离线")) {
                online = false;
                status = "OFFLINE";
                paperStatus = "UNKNOWN";
                coverStatus = "UNKNOWN";
            } else if ("2".equals(dataText) || dataText.contains("不正常") || dataText.contains("异常")) {
                online = true;
                status = "ERROR";
                if (dataText.contains("缺纸")) {
                    paperStatus = "OUT_OF_PAPER";
                } else if (dataText.contains("开盖")) {
                    coverStatus = "OPEN";
                } else {
                    paperStatus = "ERROR";
                    coverStatus = "ERROR";
                }
            } else if (dataText.contains("缺纸")) {
                online = true;
                status = "ERROR";
                paperStatus = "OUT_OF_PAPER";
            } else if (dataText.contains("开盖")) {
                online = true;
                status = "ERROR";
                coverStatus = "OPEN";
            } else if ("1".equals(dataText) || dataText.contains("正常") || dataText.contains("在线")) {
                online = true;
                status = "ONLINE";
                paperStatus = "NORMAL";
                coverStatus = "CLOSED";
            }
        }

        res.put("online", online);
        res.put("status", status);
        res.put("paperStatus", paperStatus);
        res.put("coverStatus", coverStatus);
        return res;
    }

    /** 清空云打印机待打印队列 */
    public Map<String, Object> clearDeviceQueue(int shopId, long deviceId, Integer adminId) {
        PrintingDevice device = requireDevice(shopId, deviceId);
        if (!TRANSPORT_CLOUD.equalsIgnoreCase(device.getTransport())) {
            throw new ApiException(400, "PRINTING_CLEAR_QUEUE_UNSUPPORTED", "只有云打印机(CLOUD)支持远程清空待打印队列");
        }
        String sn = connectionSn(device);
        if (feieyunService == null || StringUtil.isEmpty(sn)) {
            throw new ApiException(400, "PRINTING_SN_REQUIRED", "云打印设备 SN 码缺失或服务未就绪");
        }
        try {
            Map<String, Object> conn = parseConnection(device.getConnection_json());
            String user = conn.get("user") != null ? String.valueOf(conn.get("user")).trim() : "";
            String ukey = conn.get("ukey") != null ? String.valueOf(conn.get("ukey")).trim() : "";
            String apiUrl = conn.get("apiUrl") != null ? String.valueOf(conn.get("apiUrl")).trim() : (conn.get("url") != null ? String.valueOf(conn.get("url")).trim() : null);
            if (!user.isEmpty() && !ukey.isEmpty() && !StringUtil.isEmpty(apiUrl)) {
                feieyunService.clearPrintQueueWithCredential(apiUrl, user, ukey, sn);
            } else {
                throw new ApiException(400, "PRINTING_CLOUD_CREDENTIAL_MISSING",
                        "设备未配置飞鹅云凭据(connection.url/user/ukey)，无法清空远程队列");
            }
            log.info("[printing] clear queue success: shop_id={}, device_id={}, sn={}, admin={}",
                    shopId, deviceId, sn, adminId);
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("deviceId", deviceId);
            out.put("sn", sn);
            out.put("success", true);
            out.put("message", "待打印队列已清空");
            return out;
        } catch (Exception e) {
            String errMsg = e.getMessage() != null && !e.getMessage().trim().isEmpty() ? e.getMessage() : e.getClass().getSimpleName();
            log.warn("[printing] clear queue error: shop_id={}, device_id={}, sn={}, error={}",
                    shopId, deviceId, sn, errMsg);
            throw new ApiException(500, "PRINTING_CLEAR_QUEUE_FAILED", "清空待打印队列失败: " + errMsg);
        }
    }

    // ---------------- 规则 ----------------

    /** 规则列表 + 整体版本（本店各行 version 最大值，无规则时为 0） */
    public Map<String, Object> getRules(int shopId) {
        List<PrintingRule> rules = ruleMapper.selectList(new QueryWrapper<PrintingRule>()
                .eq("shop_id", shopId).orderByAsc("scenario"));
        return rulesPayload(shopId, rules);
    }

    /**
     * 规则列表整体保存：body = {version, rules:[{scenario, deviceId, templateCode, copies, enabled}]}。
     * 乐观锁基准为当前整体版本；通过后整组替换，新行 version = 基准 + 1。
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> saveRules(int shopId, Map<String, Object> body, Integer adminId) {
        if (body == null || body.isEmpty()) {
            throw new ApiException(400, "PRINTING_PAYLOAD_EMPTY", "请求体不能为空");
        }
        Integer expectedVersion = requireVersion(body.get("version"));
        Object rawRules = body.get("rules");
        if (!(rawRules instanceof List)) {
            throw new ApiException(400, "PRINTING_RULES_INVALID", "rules 必须为数组（可为空数组表示清空规则）");
        }
        List<PrintingRule> existingRules = ruleMapper.selectList(new QueryWrapper<PrintingRule>()
                .eq("shop_id", shopId));
        int currentVersion = rulesVersion(existingRules);
        if (expectedVersion != currentVersion) {
            throw rulesVersionConflict(shopId, existingRules, currentVersion);
        }

        List<PrintingRule> next = new ArrayList<>();
        Set<String> scenarios = new HashSet<>();
        for (Object o : (List<?>) rawRules) {
            if (!(o instanceof Map)) {
                throw new ApiException(400, "PRINTING_RULES_INVALID", "rules 内每项必须为对象");
            }
            next.add(buildRule(shopId, (Map<String, Object>) o, scenarios));
        }

        ruleMapper.delete(new QueryWrapper<PrintingRule>().eq("shop_id", shopId));
        for (PrintingRule rule : next) {
            rule.setVersion(currentVersion + 1);
            rule.setCreated_at(LocalDateTime.now(ZONE));
            rule.setUpdated_at(rule.getCreated_at());
            ruleMapper.insert(rule);
        }
        log.info("[printing] rules saved: shop_id={}, count={}, version={}->{}, admin={}",
                shopId, next.size(), currentVersion, currentVersion + 1, adminId);
        return getRules(shopId);
    }

    // ---------------- 模板管理 (C004) ----------------

    /**
     * 查询模板列表（合并系统预置模板与门店自定义模板，支持 scenario / paperSize 筛选）
     */
    public List<Map<String, Object>> getTemplates(int shopId, String scenario, String paperSize) {
        if (templateMapper == null) {
            return Collections.emptyList();
        }
        QueryWrapper<PrintingTemplate> qw = new QueryWrapper<>();
        qw.and(w -> w.eq("shop_id", shopId).or().eq("shop_id", 0));
        if (StringUtils.hasText(scenario)) {
            qw.eq("scenario", scenario.toUpperCase());
        }
        if (StringUtils.hasText(paperSize)) {
            qw.eq("paper_size", paperSize.toLowerCase());
        }
        qw.orderByAsc("scenario").orderByDesc("is_default").orderByAsc("is_system").orderByDesc("id");

        List<PrintingTemplate> list = templateMapper.selectList(qw);
        List<Map<String, Object>> results = new ArrayList<>();
        if (list != null) {
            for (PrintingTemplate pt : list) {
                results.add(templatePayload(pt));
            }
        }
        return results;
    }

    /**
     * 获取单个模板详情（含完整 JSON 配置）
     */
    public Map<String, Object> getTemplateById(int shopId, long templateId) {
        PrintingTemplate pt = requireTemplate(shopId, templateId);
        return templatePayload(pt);
    }

    /**
     * 创建自定义模板
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> createTemplate(int shopId, Map<String, Object> body, Integer adminId) {
        if (templateMapper == null) {
            throw new ApiException(500, "PRINTING_ENGINE_NOT_READY", "模板持久化模块未就绪");
        }
        String templateName = requireString(body.get("templateName"), "PRINTING_TEMPLATE_INVALID", "templateName 不能为空");
        String scenario;
        try {
            scenario = PrintScenario.canonicalCode(requireString(body.get("scenario"), "PRINTING_TEMPLATE_INVALID", "scenario 不能为空")).toUpperCase();
        } catch (IllegalArgumentException e) {
            throw new ApiException(400, "PRINTING_TEMPLATE_INVALID", e.getMessage());
        }
        String paperSize = body.get("paperSize") != null ? String.valueOf(body.get("paperSize")).toLowerCase() : "58mm";

        String templateCode = body.get("templateCode") != null ? String.valueOf(body.get("templateCode")).trim() : null;
        if (!StringUtils.hasText(templateCode)) {
            templateCode = "tpl_" + scenario.toLowerCase() + "_" + System.currentTimeMillis();
        }

        // 检查唯一性 (shop_id, template_code)
        Integer count = templateMapper.selectCount(new QueryWrapper<PrintingTemplate>()
                .eq("shop_id", shopId).eq("template_code", templateCode));
        if (count != null && count > 0) {
            throw new ApiException(409, "PRINTING_TEMPLATE_DUPLICATE_CODE", "模板编码在当前门店已存在: " + templateCode);
        }

        String templateJson = body.get("templateJson") != null ? String.valueOf(body.get("templateJson")) : null;
        if (!StringUtils.hasText(templateJson) && body.get("templateDsl") != null) {
            try {
                templateJson = objectMapper.writeValueAsString(body.get("templateDsl"));
            } catch (Exception ignored) {}
        }
        if (!StringUtils.hasText(templateJson)) {
            if (printTemplateEngine != null) {
                PrintTemplateDsl defaultDsl = printTemplateEngine.buildDefaultDsl(scenario, paperSize);
                try {
                    templateJson = objectMapper.writeValueAsString(defaultDsl);
                } catch (Exception ignored) {}
            }
            if (!StringUtils.hasText(templateJson)) {
                templateJson = "{}";
            }
        }

        boolean isDefault = Boolean.TRUE.equals(body.get("isDefault")) || Integer.valueOf(1).equals(body.get("is_default"));
        if (isDefault) {
            clearScenarioDefault(shopId, scenario);
        }

        PrintingTemplate pt = new PrintingTemplate();
        pt.setShop_id(shopId);
        pt.setTemplate_code(templateCode);
        pt.setTemplate_name(templateName);
        pt.setScenario(scenario);
        pt.setPaper_size(paperSize);
        pt.setIs_system(0);
        pt.setIs_default(isDefault ? 1 : 0);
        pt.setTemplate_json(templateJson);
        pt.setVersion(1);
        pt.setCreated_at(LocalDateTime.now(ZONE));
        pt.setUpdated_at(pt.getCreated_at());
        templateMapper.insert(pt);

        log.info("[printing] template created: shop_id={}, id={}, code={}, name={}, admin={}",
                shopId, pt.getId(), templateCode, templateName, adminId);
        return templatePayload(pt);
    }

    /**
     * 更新自定义模板（支持 version 乐观锁）
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> updateTemplate(int shopId, long templateId, Map<String, Object> body, Integer adminId) {
        PrintingTemplate pt = requireTemplate(shopId, templateId);
        if (Integer.valueOf(1).equals(pt.getIs_system()) || Integer.valueOf(0).equals(pt.getShop_id())) {
            throw new ApiException(403, "SYSTEM_TEMPLATE_READONLY", "系统内置模板不可直接修改，请克隆为自定义模板后编辑");
        }

        // 乐观锁版本校验
        if (body.containsKey("version")) {
            Integer incomingVersion = parseIntSafe(body.get("version"));
            if (incomingVersion != null && !incomingVersion.equals(pt.getVersion())) {
                Map<String, Object> errData = new LinkedHashMap<>();
                errData.put("currentVersion", pt.getVersion());
                errData.put("incomingVersion", incomingVersion);
                errData.put("template", templatePayload(pt));
                throw new ApiException(409, "PRINTING_VERSION_CONFLICT", "模板配置已被其他人修改，请刷新后重试", errData);
            }
        }

        if (body.get("templateName") != null) {
            pt.setTemplate_name(String.valueOf(body.get("templateName")).trim());
        }
        if (body.containsKey("scenario")) {
            try {
                String scenario = PrintScenario.canonicalCode(
                        requireString(body.get("scenario"), "PRINTING_TEMPLATE_INVALID", "scenario 不能为空"))
                        .toUpperCase();
                if (Integer.valueOf(1).equals(pt.getIs_default()) && !scenario.equals(pt.getScenario())) {
                    clearScenarioDefault(shopId, scenario);
                }
                pt.setScenario(scenario);
            } catch (IllegalArgumentException e) {
                throw new ApiException(400, "PRINTING_TEMPLATE_INVALID", e.getMessage());
            }
        }
        if (body.get("paperSize") != null) {
            pt.setPaper_size(String.valueOf(body.get("paperSize")).toLowerCase().trim());
        }
        if (body.get("templateJson") != null) {
            pt.setTemplate_json(String.valueOf(body.get("templateJson")));
        } else if (body.get("templateDsl") != null) {
            try {
                pt.setTemplate_json(objectMapper.writeValueAsString(body.get("templateDsl")));
            } catch (Exception ignored) {}
        }

        if (body.containsKey("isDefault") || body.containsKey("is_default")) {
            boolean isDefault = Boolean.TRUE.equals(body.get("isDefault")) || Integer.valueOf(1).equals(body.get("is_default"));
            if (isDefault) {
                clearScenarioDefault(shopId, pt.getScenario());
                pt.setIs_default(1);
            } else {
                pt.setIs_default(0);
            }
        }

        pt.setVersion(pt.getVersion() + 1);
        pt.setUpdated_at(LocalDateTime.now(ZONE));
        templateMapper.updateById(pt);

        log.info("[printing] template updated: shop_id={}, id={}, code={}, version={}->{}, admin={}",
                shopId, pt.getId(), pt.getTemplate_code(), pt.getVersion() - 1, pt.getVersion(), adminId);
        return templatePayload(pt);
    }

    /**
     * 删除自定义模板（系统内置禁止删除；被 t_printing_rule 引用的模板拦截删除）
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteTemplate(int shopId, long templateId, Integer adminId) {
        PrintingTemplate pt = requireTemplate(shopId, templateId);
        if (Integer.valueOf(1).equals(pt.getIs_system()) || Integer.valueOf(0).equals(pt.getShop_id())) {
            throw new ApiException(403, "SYSTEM_TEMPLATE_READONLY", "系统内置模板不可删除");
        }

        // 检查出票规则引用
        List<PrintingRule> refs = ruleMapper.selectList(new QueryWrapper<PrintingRule>()
                .eq("shop_id", shopId).eq("template_code", pt.getTemplate_code()));
        if (refs != null && !refs.isEmpty()) {
            List<String> scenarios = new ArrayList<>();
            for (PrintingRule r : refs) {
                scenarios.add(r.getScenario());
            }
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("templateCode", pt.getTemplate_code());
            data.put("referencingScenarios", scenarios);
            data.put("ruleCount", refs.size());
            throw new ApiException(400, "PRINT_TEMPLATE_IN_USE_BY_RULE",
                    "模板当前正被出票规则引用，请先在出票规则中更换模板后再删除", data);
        }

        templateMapper.deleteById(templateId);
        log.info("[printing] template deleted: shop_id={}, id={}, code={}, admin={}",
                shopId, templateId, pt.getTemplate_code(), adminId);
    }

    /**
     * 设为场景默认模板
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> setDefaultTemplate(int shopId, long templateId, Integer adminId) {
        PrintingTemplate pt = requireTemplate(shopId, templateId);
        clearScenarioDefault(shopId, pt.getScenario());
        pt.setIs_default(1);
        pt.setVersion(pt.getVersion() + 1);
        pt.setUpdated_at(LocalDateTime.now(ZONE));
        templateMapper.updateById(pt);
        return templatePayload(pt);
    }

    private void clearScenarioDefault(int shopId, String scenario) {
        if (templateMapper == null) return;
        List<PrintingTemplate> defaults = templateMapper.selectList(new QueryWrapper<PrintingTemplate>()
                .eq("shop_id", shopId).eq("scenario", scenario).eq("is_default", 1));
        if (defaults != null) {
            for (PrintingTemplate d : defaults) {
                d.setIs_default(0);
                d.setUpdated_at(LocalDateTime.now(ZONE));
                templateMapper.updateById(d);
            }
        }
    }

    private PrintingTemplate requireTemplate(int shopId, long templateId) {
        if (templateMapper == null) {
            throw new ApiException(500, "PRINTING_ENGINE_NOT_READY", "模板持久化模块未就绪");
        }
        PrintingTemplate pt = templateMapper.selectById(templateId);
        if (pt == null || (pt.getShop_id() != null && pt.getShop_id() != 0 && pt.getShop_id() != shopId)) {
            throw new ApiException(404, "PRINTING_TEMPLATE_NOT_FOUND", "打印模板不存在: " + templateId);
        }
        return pt;
    }

    /**
     * 模板设计器元数据（全场景参数绑定字典、积木块定义、宏变量）
     */
    public Map<String, Object> getTemplateMeta() {
        Map<String, Object> meta = new LinkedHashMap<>();

        // 1. 场景列表
        List<Map<String, Object>> scenarios = new ArrayList<>();
        scenarios.add(buildScenarioMeta("KITCHEN", "厨房小票", "后厨档口制作联，支持按菜品分类分单打印", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DISH_ITEMS", "REMARK", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("FULL_ORDER", "前台整单小票", "收银前台整单核对联/全单点菜单，含打包费与菜品明细", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DISH_ITEMS", "PAYMENT_SUMMARY", "REMARK", "MEMBER_INFO", "QRCODE", "FOOTER", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("PRE_CHECKOUT", "预结单", "顾客消费明细核对单，非结账凭据", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DISH_ITEMS", "PAYMENT_SUMMARY", "REMARK", "MEMBER_INFO", "FOOTER", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("CHECKOUT", "前台结账单", "顾客结账完成凭据，含支付方式、优惠明细与发票二维码", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DISH_ITEMS", "PAYMENT_SUMMARY", "REMARK", "MEMBER_INFO", "QRCODE", "FOOTER", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("EXPEDITE", "传菜单", "KDS 划菜与传菜出餐凭证", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DISH_ITEMS", "FOOTER", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("TAKEOUT", "外卖配送小票", "外卖配送单/骑手交接单，含顾客电话、配送地址与配送费", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DELIVERY_INFO", "DISH_ITEMS", "PAYMENT_SUMMARY", "REMARK", "QRCODE", "FOOTER", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("PACKING", "打包单", "打包/到店自提订单的独立核餐凭条，突出取餐码、餐品与备注", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "DISH_ITEMS", "REMARK", "FOOTER", "DIVIDER", "SPACING", "CUSTOM_TEXT", "CUT")));
        scenarios.add(buildScenarioMeta("SHIFT", "收银交接班报表", "收银员当班结账汇总、备用金与各渠道收款报表", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "CUSTOM_TEXT", "DIVIDER", "SPACING", "QRCODE", "FOOTER", "CUT")));
        scenarios.add(buildScenarioMeta("REFUND", "退款单据", "订单退款凭证与审核单", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "ORDER_INFO", "CUSTOM_TEXT", "DIVIDER", "SPACING", "QRCODE", "FOOTER", "CUT")));
        scenarios.add(buildScenarioMeta("LABEL", "商品标签杯贴", "商品外包装贴纸/奶茶杯贴/烧烤餐盒标", Arrays.asList("58mm", "label"),
                Arrays.asList("HEADER", "CUSTOM_TEXT", "QRCODE", "BARCODE", "DIVIDER", "SPACING", "FOOTER", "CUT")));
        scenarios.add(buildScenarioMeta("TEST", "打印测试单", "打印机自检与驱动连通性测试", Arrays.asList("58mm", "80mm"),
                Arrays.asList("HEADER", "CUSTOM_TEXT", "DIVIDER", "SPACING", "FOOTER", "CUT")));
        meta.put("scenarios", scenarios);

        // 2. 场景专属变量字典
        Map<String, List<Map<String, Object>>> paramsByScenario = new LinkedHashMap<>();
        paramsByScenario.put("SHIFT", Arrays.asList(
                buildParamVar("shiftId", "{班次ID}", "班次流水号", "Integer", "101"),
                buildParamVar("shopId", "{门店ID}", "所属门店编号", "Integer", "1"),
                buildParamVar("adminId", "{收银员ID}", "交班收银员账号 ID", "Integer", "8"),
                buildParamVar("startTime", "{开班时间}", "开班打卡签到时间", "String", "2026-09-02 08:00:00"),
                buildParamVar("endTime", "{交班时间}", "交班打卡结账时间", "String", "2026-09-02 16:00:00"),
                buildParamVar("startCash", "{备用金}", "开班备用金金额（元）", "Double", "300.00"),
                buildParamVar("orderCount", "{总单数}", "当班完成订单总数", "Integer", "42"),
                buildParamVar("totalAmount", "{实收总额}", "当班实收营业额合计（元）", "Double", "2580.00"),
                buildParamVar("wechatAmount", "{微信收款}", "微信支付渠道实收（元）", "Double", "1680.00"),
                buildParamVar("alipayAmount", "{支付宝收款}", "支付宝渠道实收（元）", "Double", "580.00"),
                buildParamVar("cashAmount", "{现金收款}", "现金支付实收（元）", "Double", "320.00"),
                buildParamVar("memberAmount", "{会员收款}", "会员余额消费金额（元）", "Double", "0.00"),
                buildParamVar("totalRefund", "{退款总额}", "当班退款总金额（元）", "Double", "68.00"),
                buildParamVar("printTime", "{打印时间}", "报表生成打印时间", "String", "2026-09-02 16:05:00")
        ));

        paramsByScenario.put("REFUND", Arrays.asList(
                buildParamVar("orderNo", "{原订单号}", "关联原订单编号", "String", "ORD-20260902-001"),
                buildParamVar("tableNo", "{桌号}", "原餐桌号或外卖标识", "String", "A08"),
                buildParamVar("refundAmount", "{退款金额}", "本次退款金额（元）", "Double", "48.00"),
                buildParamVar("reason", "{退款原因}", "退款原因与说明", "String", "菜品估清退款"),
                buildParamVar("operator", "{操作人员}", "审核与退款操作人", "String", "收银员小张"),
                buildParamVar("refundTime", "{退款时间}", "退款成功时间", "String", "2026-09-02 15:30:00")
        ));

        paramsByScenario.put("LABEL", Arrays.asList(
                buildParamVar("goodsName", "{品名}", "菜品/商品名称", "String", "招牌烤油边(大份)"),
                buildParamVar("spec", "{规格}", "辣度/口味/加料规格", "String", "(微辣,烤焦一点)"),
                buildParamVar("quantity", "{数量}", "商品份数", "Integer", "2"),
                buildParamVar("price", "{单价}", "商品金额（元）", "Double", "48.00"),
                buildParamVar("tableNo", "{桌号}", "桌台号或取餐号", "String", "A08"),
                buildParamVar("orderNo", "{订单号}", "订单业务编号", "String", "ORD-20260902-001"),
                buildParamVar("time", "{时间}", "出标时间", "String", "2026-09-02 15:30:00")
        ));

        List<Map<String, Object>> commonOrderVars = Arrays.asList(
                buildParamVar("tableNo", "{桌号}", "桌台号/自提号", "String", "A08"),
                buildParamVar("orderNo", "{订单号}", "系统订单编号", "String", "ORD-20260902-001"),
                buildParamVar("orderId", "{订单ID}", "订单数据库主键", "Integer", "10086"),
                buildParamVar("dineInType", "{用餐方式}", "用餐场景（堂食/打包/外卖）", "String", "堂食"),
                buildParamVar("isAddDish", "{加菜}", "是否为加菜单", "String", "【加菜】"),
                buildParamVar("orderTime", "{下单时间}", "顾客下单时间", "String", "2026-09-02 12:30:00"),
                buildParamVar("payTime", "{结账时间}", "支付完成时间", "String", "2026-09-02 12:30:15"),
                buildParamVar("remark", "{备注}", "订单口味与特殊要求备注", "String", "微辣，少放香菜"),
                buildParamVar("originalAmount", "{原价}", "菜品原价小计金额", "Double", "168.00"),
                buildParamVar("discountAmount", "{优惠}", "折扣优惠券减免金额", "Double", "10.00"),
                buildParamVar("settAmount", "{实付}", "顾客实付应收总额", "Double", "158.00"),
                buildParamVar("payMethod", "{支付方式}", "支付渠道名称", "String", "微信支付"),
                buildParamVar("receiverName", "{收件人}", "外卖顾客姓名", "String", "王先生"),
                buildParamVar("receiverPhone", "{收件人电话}", "外卖联系电话", "String", "138****5678"),
                buildParamVar("deliveryAddress", "{配送地址}", "外卖收货详细地址", "String", "阳光花园二期8栋1202室"),
                buildParamVar("deliveryFee", "{配送费}", "外卖配送运费（元）", "Double", "5.00"),
                buildParamVar("packagingFee", "{打包费}", "餐盒打包费（元）", "Double", "2.00")
        );
        paramsByScenario.put("ORDER", commonOrderVars);
        paramsByScenario.put("CHECKOUT", commonOrderVars);
        paramsByScenario.put("FULL_ORDER", commonOrderVars);
        paramsByScenario.put("PRE_CHECKOUT", commonOrderVars);
        paramsByScenario.put("TAKEOUT", commonOrderVars);
        paramsByScenario.put("PACKING", commonOrderVars);
        paramsByScenario.put("KITCHEN", commonOrderVars);
        paramsByScenario.put("EXPEDITE", commonOrderVars);
        paramsByScenario.put("TEST", commonOrderVars);

        meta.put("parametersByScenario", paramsByScenario);
        return meta;
    }

    private Map<String, Object> buildScenarioMeta(String code, String name, String desc, List<String> papers, List<String> blocks) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("code", code);
        s.put("name", name);
        s.put("description", desc);
        s.put("supportedPaperSizes", papers);
        s.put("allowedBlocks", blocks);
        return s;
    }

    private Map<String, Object> buildParamVar(String key, String placeholder, String desc, String type, String example) {
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("key", key);
        p.put("placeholder", placeholder);
        p.put("aliases", Arrays.asList("{" + key + "}", placeholder));
        p.put("name", desc);
        p.put("description", desc);
        p.put("type", type);
        p.put("example", example);
        return p;
    }

    private Map<String, Object> templatePayload(PrintingTemplate pt) {
        Map<String, Object> map = new LinkedHashMap<>();
        if (pt == null) return map;
        map.put("id", pt.getId());
        map.put("shopId", pt.getShop_id());
        map.put("templateCode", pt.getTemplate_code());
        map.put("templateName", pt.getTemplate_name());
        map.put("scenario", pt.getScenario());
        map.put("paperSize", pt.getPaper_size());
        map.put("isSystem", Integer.valueOf(1).equals(pt.getIs_system()));
        map.put("isDefault", Integer.valueOf(1).equals(pt.getIs_default()));
        map.put("version", pt.getVersion());
        map.put("templateJson", pt.getTemplate_json());
        if (StringUtils.hasText(pt.getTemplate_json()) && printTemplateEngine != null) {
            PrintTemplateDsl dsl = printTemplateEngine.parseDsl(pt.getTemplate_json());
            if (dsl != null) {
                map.put("templateDsl", dsl);
            }
        }
        if (pt.getCreated_at() != null) {
            map.put("createdAt", pt.getCreated_at().format(DATETIME));
        }
        if (pt.getUpdated_at() != null) {
            map.put("updatedAt", pt.getUpdated_at().format(DATETIME));
        }
        return map;
    }

    // ---------------- 打印测试 ----------------

    /**
     * 打印测试：生成测试单文本并落 t_printing_job。
     * CLOUD：调用既有飞鹅打印服务，成功 → SENT；未配置/失败 → FAILED + error。
     * LAN/USB/BLUETOOTH：PENDING_DEVICE + executor=DEVICE，由端侧执行。
     * 返回 {jobId, status, executor, message}。
     */
    public Map<String, Object> createTestJob(int shopId, long deviceId, String testType, Integer adminId) {
        return createTestJob(shopId, deviceId, testType, null, adminId);
    }

    public Map<String, Object> createTestJob(int shopId, long deviceId, String testType, String customContent, Integer adminId) {
        PrintingDevice device = requireDevice(shopId, deviceId);
        String type = normalizeTestType(testType);
        String payload = StringUtil.isEmpty(customContent) ? buildTestPayload(type, device) : customContent;

        PrintingJob job = new PrintingJob();
        job.setShop_id(shopId);
        job.setDevice_id(deviceId);
        job.setJob_type(type);
        job.setPayload_text(payload);
        job.setRetry_count(0);
        job.setCreated_at(LocalDateTime.now(ZONE));
        job.setUpdated_at(job.getCreated_at());

        if (TRANSPORT_CLOUD.equals(device.getTransport())) {
            job.setExecutor("CLOUD");
            String sn = connectionSn(device);
            if (feieyunService == null || StringUtil.isEmpty(sn)) {
                job.setStatus(STATUS_FAILED);
                job.setError(CLOUD_NOT_CONFIGURED);
            } else {
                try {
                    Map<String, Object> conn = parseConnection(device.getConnection_json());
                    String user = conn.get("user") != null ? String.valueOf(conn.get("user")).trim() : null;
                    String ukey = conn.get("ukey") != null ? String.valueOf(conn.get("ukey")).trim() : null;
                    String apiUrl = conn.get("url") != null ? String.valueOf(conn.get("url")).trim() : null;
                    if (StringUtil.isEmpty(apiUrl) && conn.get("apiUrl") != null) {
                        apiUrl = String.valueOf(conn.get("apiUrl")).trim();
                    }

                    if (StringUtil.isEmpty(user) || StringUtil.isEmpty(ukey)) {
                        throw new IOException("设备未配置飞鹅云凭据(connection.user/ukey)，无法云端打印");
                    }
                    if (StringUtil.isEmpty(apiUrl)) {
                        throw new IOException("设备未配置飞鹅云接口地址(connection.url/apiUrl)，无法云端打印");
                    }
                    feieyunService.printWithCredential(apiUrl, user, ukey, sn, payload, 1);
                    job.setStatus(STATUS_SENT);
                } catch (IOException e) {
                    log.warn("[printing] cloud print failed: shop_id={}, device_id={}, msg={}",
                            shopId, deviceId, e.getMessage());
                    job.setStatus(STATUS_FAILED);
                    job.setError(truncate(e.getMessage() == null ? "cloud print failed" : e.getMessage()));
                } catch (Exception e) {
                    // 门店/全局飞鹅配置缺失等运行时异常同样不阻断任务落库
                    log.warn("[printing] cloud print error: shop_id={}, device_id={}, msg={}",
                            shopId, deviceId, e.getMessage());
                    job.setStatus(STATUS_FAILED);
                    job.setError(truncate(e.getMessage() == null ? CLOUD_NOT_CONFIGURED : e.getMessage()));
                }
            }
        } else {
            job.setExecutor("DEVICE");
            job.setStatus(STATUS_PENDING_DEVICE);
        }

        jobMapper.insert(job);
        log.info("[printing] test job created: shop_id={}, device_id={}, job={}, status={}, executor={}, admin={}",
                shopId, deviceId, job.getId(), job.getStatus(), job.getExecutor(), adminId);

        String jobCode = "JOB-PRINT-" + LocalDate.now(ZONE).format(DateTimeFormatter.ofPattern("yyyyMMdd")) + "-" + job.getId();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("jobId", job.getId());
        out.put("jobCode", jobCode);
        out.put("id", job.getId());
        out.put("deviceId", deviceId);
        out.put("status", job.getStatus());
        out.put("executor", job.getExecutor());
        out.put("message", STATUS_SENT.equals(job.getStatus()) ? "已向飞鹅云平台成功提交打印指令包" : "测试出票指令已下发");
        out.put("error", job.getError());
        out.put("payloadText", payload);
        return out;
    }

    // ---------------- 任务记录 ----------------

    /** 任务列表：时间范围/device_id/status 筛选 + 分页。无任何重启/重试触发能力。 */
    public PageResult listJobs(int shopId, String status, Long deviceId,
                               String startTime, String endTime, int page, int pageSize) {
        int[] pp = normalizePage(page, pageSize);
        QueryWrapper<PrintingJob> qw = new QueryWrapper<>();
        qw.eq("shop_id", shopId);
        if (!StringUtil.isEmpty(status)) {
            String s = status.trim().toUpperCase();
            if (!JOB_STATUSES.contains(s)) {
                throw new ApiException(400, "PRINTING_STATUS_INVALID",
                        "status 仅支持 PENDING_DEVICE/SENT/PRINTED/FAILED/CANCELED");
            }
            qw.eq("status", s);
        }
        if (deviceId != null) {
            qw.eq("device_id", deviceId);
        }
        if (!StringUtil.isEmpty(startTime)) {
            qw.ge("created_at", parseTime(startTime, "startTime"));
        }
        if (!StringUtil.isEmpty(endTime)) {
            qw.le("created_at", parseTime(endTime, "endTime"));
        }
        qw.orderByDesc("id");
        Page<PrintingJob> result = jobMapper.selectPage(new Page<>(pp[0], pp[1]), qw);
        List<Map<String, Object>> items = new ArrayList<>();
        if (result.getRecords() != null) {
            for (PrintingJob j : result.getRecords()) {
                items.add(jobSummary(j));
            }
        }
        return PageResult.of(pp[0], pp[1], result.getTotal(), items);
    }

    // ---------------- 摘要与脱敏 ----------------

    /** 设备摘要：包含平铺字段与脱敏后的 connection 对象 */
    public Map<String, Object> deviceSummary(PrintingDevice device) {
        Map<String, Object> m = new LinkedHashMap<>();
        Map<String, Object> conn = parseConnection(device.getConnection_json());
        Map<String, Object> maskedConn = maskConnection(conn);

        m.put("id", device.getId());
        m.put("shopId", device.getShop_id());
        m.put("shopName", resolveShopName(device.getShop_id()));
        m.put("name", device.getName());
        m.put("transport", device.getTransport());
        m.put("brand", device.getBrand());
        m.put("vendor", device.getBrand() != null ? device.getBrand() : "");
        m.put("status", device.getStatus());
        m.put("version", device.getVersion());

        // 平铺便利字段
        m.put("sn", conn.get("sn") != null ? String.valueOf(conn.get("sn")) : (maskedConn.get("sn") != null ? String.valueOf(maskedConn.get("sn")) : ""));
        m.put("user", conn.get("user") != null ? String.valueOf(conn.get("user")) : "");
        m.put("ukey", maskedConn.get("ukey") != null ? String.valueOf(maskedConn.get("ukey")) : (maskedConn.get("key") != null ? String.valueOf(maskedConn.get("key")) : ""));
        m.put("apiUrl", conn.get("apiUrl") != null ? String.valueOf(conn.get("apiUrl")) : (conn.get("url") != null ? String.valueOf(conn.get("url")) : ""));
        m.put("ip", conn.get("ip") != null ? String.valueOf(conn.get("ip")) : "");
        m.put("port", conn.get("port") instanceof Number ? ((Number) conn.get("port")).intValue() : (conn.get("port") != null ? conn.get("port") : 9100));
        m.put("paperSize", conn.get("paperSize") != null ? String.valueOf(conn.get("paperSize")) : "80mm");
        m.put("copies", conn.get("copies") instanceof Number ? ((Number) conn.get("copies")).intValue() : 1);
        m.put("autoCut", conn.get("autoCut") instanceof Boolean ? (Boolean) conn.get("autoCut") : true);
        m.put("beeper", conn.get("beeper") instanceof Boolean ? (Boolean) conn.get("beeper") : true);
        m.put("enabled", conn.get("enabled") instanceof Boolean ? (Boolean) conn.get("enabled") : true);
        m.put("isDefault", conn.get("isDefault") instanceof Boolean ? (Boolean) conn.get("isDefault") : false);
        m.put("ticketTypes", normalizeTicketTypes(conn.get("ticketTypes")));

        m.put("connection", maskedConn);
        m.put("createdAt", iso(device.getCreated_at()));
        m.put("updatedAt", iso(device.getUpdated_at()));
        m.put("updatedBy", "admin");
        return m;
    }

    private String resolveShopName(Integer shopId) {
        if (shopId == null || shopService == null) {
            return "";
        }
        try {
            com.lanf.entity.Shop shop = shopService.getById(shopId);
            return shop != null && shop.getName() != null ? shop.getName() : "";
        } catch (Exception e) {
            return "";
        }
    }

    private Map<String, Object> jobSummary(PrintingJob job) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", job.getId());
        m.put("shopId", job.getShop_id());
        m.put("deviceId", job.getDevice_id());
        String canonicalJobType = PrintScenario.canonicalCode(job.getJob_type());
        m.put("jobType", canonicalJobType);
        m.put("scenarioName", PrintScenario.displayName(canonicalJobType));
        m.put("customScenario", !PrintScenario.isBuiltIn(canonicalJobType));
        if (!canonicalJobType.equals(job.getJob_type())) {
            m.put("legacyJobType", job.getJob_type());
        }
        m.put("status", job.getStatus());
        m.put("executor", job.getExecutor());
        m.put("error", job.getError());
        if (job.getBiz_type() != null) {
            m.put("bizType", job.getBiz_type());
        }
        if (job.getBiz_id() != null) {
            m.put("bizId", job.getBiz_id());
        }
        m.put("retryCount", job.getRetry_count());
        m.put("payloadText", job.getPayload_text());
        m.put("createdAt", iso(job.getCreated_at()));
        m.put("updatedAt", iso(job.getUpdated_at()));
        return m;
    }

    /**
     * connection 脱敏：密钥类（key/secret/token/password）→ ****；
     * 序列号与普通参数原样返回，ticketTypes 归一化为枚举数组。
     */
    public static Map<String, Object> maskConnection(Map<String, Object> connection) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (connection == null) {
            return out;
        }
        for (Map.Entry<String, Object> e : connection.entrySet()) {
            String key = e.getKey() == null ? "" : e.getKey();
            String lower = key.toLowerCase();
            if (lower.equals("key") || lower.endsWith("key") || lower.equals("ukey")
                    || lower.contains("secret") || lower.contains("token") || lower.contains("password")) {
                out.put(key, maskSecret(e.getValue()));
            } else if (lower.equals("tickettypes")) {
                out.put(key, normalizeTicketTypes(e.getValue()));
            } else {
                out.put(key, e.getValue());
            }
        }
        return out;
    }

    /** 归一化并校验票据类型数组 */
    public static List<String> normalizeTicketTypes(Object raw) {
        if (raw == null) {
            return new ArrayList<>();
        }
        List<String> list = new ArrayList<>();
        if (raw instanceof List) {
            for (Object o : (List<?>) raw) {
                if (o != null) {
                    String s = canonicalTicketTypeOrNull(o.toString());
                    if (s != null && !list.contains(s)) {
                        list.add(s);
                    }
                }
            }
        } else if (raw instanceof String[]) {
            for (String s : (String[]) raw) {
                if (s != null) {
                    String clean = canonicalTicketTypeOrNull(s);
                    if (clean != null && !list.contains(clean)) {
                        list.add(clean);
                    }
                }
            }
        } else if (raw instanceof String) {
            String str = ((String) raw).trim();
            if (str.isEmpty() || "null".equalsIgnoreCase(str) || "[]".equals(str)) {
                return list;
            }
            if (str.startsWith("[") && str.endsWith("]")) {
                try {
                    ObjectMapper mapper = new ObjectMapper();
                    List<String> parsed = mapper.readValue(str, new TypeReference<List<String>>() {});
                    return normalizeTicketTypes(parsed);
                } catch (Exception ignore) {
                    // fall through
                }
            }
            String[] parts = str.split("[,;，]");
            for (String p : parts) {
                String clean = canonicalTicketTypeOrNull(p.trim().replaceAll("[\"'\\[\\]]", ""));
                if (clean != null && !list.contains(clean)) {
                    list.add(clean);
                }
            }
        }
        return list;
    }

    private static String canonicalTicketTypeOrNull(String raw) {
        try {
            return PrintScenario.canonicalCode(raw).toUpperCase();
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    /** 掩码密钥（保留前4后4或全部掩码） */
    static String maskSecret(Object value) {
        String s = value == null ? "" : String.valueOf(value);
        if (s.length() <= 8) {
            return "****";
        }
        return s.substring(0, 4) + "****" + s.substring(s.length() - 4);
    }

    /** 只保留末尾 keep 位，其余以 **** 掩盖；不足 keep 位时整体掩码 */
    static String maskTail(Object value, int keep) {
        String s = value == null ? "" : String.valueOf(value);
        if (s.length() <= keep) {
            return "****";
        }
        return "****" + s.substring(s.length() - keep);
    }

    /** 检查 SN 是否重复 */
    private void checkSnUniqueness(int shopId, Long excludeDeviceId, String sn) {
        List<PrintingDevice> devices = deviceMapper.selectList(new QueryWrapper<PrintingDevice>()
                .eq("shop_id", shopId));
        if (devices != null) {
            for (PrintingDevice d : devices) {
                if (excludeDeviceId != null && d.getId().equals(excludeDeviceId)) {
                    continue;
                }
                String dSn = connectionSn(d);
                if (sn.equalsIgnoreCase(dSn)) {
                    throw new ApiException(400, "PRINT_DEVICE_DUPLICATE_SN", "设备 SN 码已被其他打印机绑定: " + sn);
                }
            }
        }
    }

    /** 合并顶层连接配置字段到 connection Map */
    private boolean mergeFlatConnectionFields(Map<String, Object> source, Map<String, Object> target) {
        boolean changed = false;
        String[] fields = {"sn", "user", "ukey", "key", "apiUrl", "url", "ip", "port", "paperSize", "copies", "autoCut", "beeper", "enabled", "isDefault", "ticketTypes"};
        for (String field : fields) {
            if (source.containsKey(field) && source.get(field) != null) {
                changed = true;
                Object val = source.get(field);
                if ("ukey".equals(field) || "key".equals(field)) {
                    String strVal = val.toString().trim();
                    // 若传入的是掩码（含 ****）或空字符串，则保留历史密文
                    if (strVal.contains("****") || strVal.isEmpty()) {
                        continue;
                    }
                }
                if ("ticketTypes".equals(field)) {
                    val = normalizeTicketTypes(val);
                }
                target.put(field, val);
            }
        }
        return changed;
    }

    /** 合并传入的连接参数并保护历史密钥不被掩码覆盖 */
    private void mergePreservingSecrets(Map<String, Object> existingConn, Map<String, Object> incomingConn) {
        if (incomingConn == null) {
            return;
        }
        for (Map.Entry<String, Object> entry : incomingConn.entrySet()) {
            String key = entry.getKey();
            Object val = entry.getValue();
            if (val != null) {
                String strVal = val.toString().trim();
                String lower = key.toLowerCase();
                if (lower.equals("key") || lower.endsWith("key") || lower.equals("ukey")
                        || lower.contains("secret") || lower.contains("token") || lower.contains("password")) {
                    if (strVal.contains("****") || strVal.isEmpty()) {
                        // 保留原有密文
                        continue;
                    }
                } else if (lower.equals("tickettypes")) {
                    val = normalizeTicketTypes(val);
                }
                existingConn.put(key, val);
            }
        }
    }

    // ---------------- 内部工具 ----------------

    private Map<String, Object> rulesPayload(int shopId, List<PrintingRule> rules) {
        List<Map<String, Object>> items = new ArrayList<>();
        LocalDateTime latest = null;
        int version = 0;
        if (rules != null) {
            for (PrintingRule r : rules) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("id", r.getId());
                item.put("scenario", r.getScenario());
                item.put("deviceId", r.getDevice_id());
                item.put("templateCode", r.getTemplate_code());
                item.put("copies", r.getCopies());
                item.put("enabled", r.getEnabled() != null && r.getEnabled() == 1);
                item.put("version", r.getVersion());
                item.put("updatedAt", iso(r.getUpdated_at()));
                items.add(item);
                if (r.getVersion() != null && r.getVersion() > version) {
                    version = r.getVersion();
                }
                if (r.getUpdated_at() != null && (latest == null || r.getUpdated_at().isAfter(latest))) {
                    latest = r.getUpdated_at();
                }
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("shopId", shopId);
        out.put("version", version);
        out.put("updatedAt", iso(latest));
        out.put("rules", items);
        return out;
    }

    private PrintingRule buildRule(int shopId, Map<String, Object> raw, Set<String> scenarios) {
        String scenario = requireString(raw.get("scenario"), "PRINTING_RULE_INVALID", "规则 scenario 不能为空");
        try {
            scenario = PrintScenario.canonicalCode(scenario);
        } catch (IllegalArgumentException e) {
            throw new ApiException(400, "PRINTING_RULE_INVALID", e.getMessage());
        }
        if (!scenarios.add(scenario)) {
            throw new ApiException(400, "PRINTING_RULE_INVALID", "规则 scenario 重复：" + scenario);
        }
        PrintingRule rule = new PrintingRule();
        rule.setShop_id(shopId);
        rule.setScenario(scenario);
        rule.setDevice_id(optionalDeviceId(raw.get("deviceId"), shopId));
        String templateCode = optionalString(raw.get("templateCode"), 64,
                "PRINTING_RULE_INVALID", "templateCode 不能超过 64 字符");
        validateRuleTemplate(shopId, templateCode);
        rule.setTemplate_code(templateCode);
        int copies = 1;
        if (raw.get("copies") instanceof Number) {
            copies = ((Number) raw.get("copies")).intValue();
        }
        if (copies < 1 || copies > 9) {
            throw new ApiException(400, "PRINTING_RULE_INVALID", "规则 copies 必须在 1-9 之间");
        }
        rule.setCopies(copies);
        boolean enabled = !(raw.get("enabled") instanceof Boolean) || (Boolean) raw.get("enabled");
        rule.setEnabled(enabled ? 1 : 0);
        return rule;
    }

    /** 规则只能引用当前门店或系统模板；规则场景与模板版式可独立组合。 */
    private void validateRuleTemplate(int shopId, String templateCode) {
        if (!StringUtils.hasText(templateCode)) {
            return;
        }
        if (templateMapper == null) {
            throw new ApiException(500, "PRINTING_ENGINE_NOT_READY", "模板持久化模块未就绪");
        }
        PrintingTemplate template = templateMapper.selectOne(new QueryWrapper<PrintingTemplate>()
                .eq("template_code", templateCode)
                .and(w -> w.eq("shop_id", shopId).or().eq("shop_id", 0)));
        if (template == null) {
            throw new ApiException(400, "PRINTING_RULE_TEMPLATE_NOT_FOUND",
                    "规则引用的模板不存在或不属于当前门店：" + templateCode);
        }
    }

    /** 规则引用的设备必须属于当前门店 */
    private Long optionalDeviceId(Object raw, int shopId) {
        if (raw == null) {
            return null;
        }
        long deviceId;
        if (raw instanceof Number) {
            deviceId = ((Number) raw).longValue();
        } else if (raw instanceof String && !((String) raw).trim().isEmpty()) {
            try {
                deviceId = Long.parseLong(((String) raw).trim());
            } catch (NumberFormatException e) {
                throw new ApiException(400, "PRINTING_RULE_INVALID", "deviceId 必须为整数");
            }
        } else {
            return null;
        }
        PrintingDevice device = deviceMapper.selectById(deviceId);
        if (device == null || device.getShop_id() == null || device.getShop_id() != shopId) {
            throw new ApiException(400, "PRINTING_DEVICE_NOT_IN_SHOP",
                    "规则引用的设备不存在或不属于当前门店：" + deviceId);
        }
        return deviceId;
    }

    private ApiException deviceVersionConflict(PrintingDevice latest) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("deviceId", latest.getId());
        data.put("name", latest.getName());
        data.put("status", latest.getStatus());
        data.put("version", latest.getVersion());
        data.put("connection", maskConnection(parseConnection(latest.getConnection_json())));
        data.put("updatedAt", iso(latest.getUpdated_at()));
        return new ApiException(409, "PRINTING_VERSION_CONFLICT",
                "配置已被他人修改，请展示差异并重新加载", data);
    }

    private ApiException rulesVersionConflict(int shopId, List<PrintingRule> existing, int currentVersion) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("shopId", shopId);
        data.put("version", currentVersion);
        data.put("ruleCount", existing == null ? 0 : existing.size());
        return new ApiException(409, "PRINTING_VERSION_CONFLICT",
                "配置已被他人修改，请展示差异并重新加载", data);
    }

    private PrintingDevice requireDevice(int shopId, long deviceId) {
        PrintingDevice device = deviceMapper.selectById(deviceId);
        if (device == null || device.getShop_id() == null || device.getShop_id() != shopId) {
            throw new ApiException(404, "PRINTING_DEVICE_NOT_FOUND", "打印设备不存在");
        }
        return device;
    }

    private String normalizeTestType(String testType) {
        String type = StringUtil.isEmpty(testType) ? "order" : testType.trim().toLowerCase();
        if (!type.matches("[a-z0-9_-]{1,32}")) {
            throw new ApiException(400, "PRINTING_TEST_TYPE_INVALID",
                    "testType 仅支持 1-32 位小写字母/数字/中划线/下划线");
        }
        return type;
    }

    /** 生成测试单文本（58mm 热敏小票样式的打印测试单） */
    String buildTestPayload(String type, PrintingDevice device) {
        StringBuilder sb = new StringBuilder();
        sb.append("==========\n");
        sb.append("打印测试单\n");
        sb.append("==========\n");
        sb.append("类型: ").append(type).append("\n");
        sb.append("门店: #").append(device.getShop_id()).append("\n");
        sb.append("设备: ").append(device.getName())
                .append(" (").append(device.getTransport()).append(")\n");
        if (!StringUtil.isEmpty(device.getBrand())) {
            sb.append("品牌: ").append(device.getBrand()).append("\n");
        }
        sb.append("时间: ").append(LocalDateTime.now(ZONE).format(DATETIME)).append("\n");
        sb.append("--------------------------\n");
        if ("refund".equals(type)) {
            sb.append("测试退款单\n");
            sb.append("原单号: TEST-000001\n");
            sb.append("退款金额: ¥0.01\n");
        } else if ("shift".equals(type)) {
            sb.append("测试交接班单\n");
            sb.append("班次: TEST-SHIFT\n");
        } else if ("kitchen".equals(type)) {
            sb.append("测试后厨单\n");
            sb.append("1x 测试菜品（免做得）\n");
        } else {
            sb.append("1x 测试商品   ¥10.00\n");
            sb.append("2x 测试商品B  ¥28.00\n");
            sb.append("--------------------------\n");
            sb.append("合计: ¥38.00\n");
        }
        sb.append("--------------------------\n");
        sb.append("**打印模块联调测试，非真实单据**\n");
        return sb.toString();
    }

    private String connectionSn(PrintingDevice device) {
        Map<String, Object> connection = parseConnection(device.getConnection_json());
        Object sn = connection.get("sn");
        return sn == null ? null : String.valueOf(sn).trim();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parseConnection(Object raw) {
        if (raw == null) {
            return new LinkedHashMap<>();
        }
        if (raw instanceof Map) {
            return (Map<String, Object>) raw;
        }
        String s = String.valueOf(raw).trim();
        if (s.isEmpty() || "null".equalsIgnoreCase(s)) {
            return new LinkedHashMap<>();
        }
        try {
            return objectMapper.readValue(s, new TypeReference<LinkedHashMap<String, Object>>() {
            });
        } catch (Exception e) {
            throw new ApiException(400, "PRINTING_CONNECTION_INVALID",
                    "connection 必须为对象或 JSON 对象字符串");
        }
    }

    private String json(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload == null ? new LinkedHashMap<>() : payload);
        } catch (Exception e) {
            throw new ApiException(500, "PRINTING_SERIALIZE_FAILED", "连接参数序列化失败");
        }
    }

    private String requireTransport(Object raw) {
        String transport = requireString(raw, "PRINTING_TRANSPORT_REQUIRED", "transport 不能为空");
        String t = transport.trim().toUpperCase();
        if (!TRANSPORTS.contains(t)) {
            throw new ApiException(400, "PRINTING_TRANSPORT_INVALID", "transport 仅支持 LAN/USB/BLUETOOTH/CLOUD");
        }
        return t;
    }

    private String optionalStatus(Object raw) {
        if (raw == null || String.valueOf(raw).trim().isEmpty()) {
            return "UNKNOWN";
        }
        String s = String.valueOf(raw).trim().toUpperCase();
        if (!DEVICE_STATUSES.contains(s)) {
            throw new ApiException(400, "PRINTING_STATUS_INVALID", "status 仅支持 ONLINE/OFFLINE/ERROR/UNKNOWN");
        }
        return s;
    }

    private Integer requireVersion(Object raw) {
        if (raw instanceof Number) {
            int v = ((Number) raw).intValue();
            if (v < 0) {
                throw new ApiException(400, "PRINTING_VERSION_INVALID", "version 必须为非负整数");
            }
            return v;
        }
        if (raw instanceof String && !((String) raw).trim().isEmpty()) {
            try {
                return Integer.parseInt(((String) raw).trim());
            } catch (NumberFormatException e) {
                throw new ApiException(400, "PRINTING_VERSION_INVALID", "version 必须为整数");
            }
        }
        throw new ApiException(400, "PRINTING_VERSION_REQUIRED", "更新请求必须携带 version 乐观锁");
    }

    private String requireString(Object raw, String errorCode, String msg) {
        if (raw == null || String.valueOf(raw).trim().isEmpty()) {
            throw new ApiException(400, errorCode, msg);
        }
        return String.valueOf(raw).trim();
    }

    private String optionalString(Object raw, int maxLen, String errorCode, String msg) {
        if (raw == null) {
            return null;
        }
        String s = String.valueOf(raw).trim();
        if (s.isEmpty() || "null".equalsIgnoreCase(s)) {
            return null;
        }
        if (s.length() > maxLen) {
            throw new ApiException(400, errorCode, msg);
        }
        return s;
    }

    private int rulesVersion(List<PrintingRule> rules) {
        int version = 0;
        if (rules != null) {
            for (PrintingRule r : rules) {
                if (r.getVersion() != null && r.getVersion() > version) {
                    version = r.getVersion();
                }
            }
        }
        return version;
    }

    private LocalDateTime parseTime(String raw, String field) {
        String s = raw.trim();
        try {
            return LocalDateTime.parse(s);
        } catch (Exception ignore) {
            // fall through
        }
        try {
            return LocalDateTime.parse(s, DATETIME);
        } catch (Exception ignore) {
            // fall through
        }
        try {
            return LocalDate.parse(s).atStartOfDay();
        } catch (Exception ignore) {
            // fall through
        }
        throw new ApiException(400, "PRINTING_TIME_INVALID",
                field + " 仅支持 yyyy-MM-dd、yyyy-MM-dd HH:mm:ss 或 ISO-8601 格式");
    }

    private int[] normalizePage(int page, int pageSize) {
        int p = page < 1 ? 1 : page;
        int size = pageSize < 1 ? 20 : Math.min(pageSize, MAX_PAGE_SIZE);
        return new int[]{p, size};
    }

    private String truncate(String s) {
        if (s == null) {
            return null;
        }
        return s.length() > 480 ? s.substring(0, 480) : s;
    }

    // ---------------- 打印预览 ----------------

    /**
     * 小票打印实时预览（返回组装好的打印数据，前端可直接解析预览）
     */
    public PrintPreviewResult previewPrint(int shopId, Map<String, Object> params) {
        if (params == null) {
            params = new LinkedHashMap<>();
        }

        String rawScenario = params.get("scenario") != null ? String.valueOf(params.get("scenario")).trim() : "ORDER";
        String scenario = rawScenario.toUpperCase();

        // 1. 确定纸张规格与设备配置
        Long deviceId = params.get("deviceId") != null ? parseLongSafe(params.get("deviceId")) : null;
        PrintingDevice device = null;
        if (deviceId != null) {
            device = deviceMapper.selectById(deviceId);
        }

        String paperSize = "58mm";
        if (params.get("paperSize") != null) {
            paperSize = String.valueOf(params.get("paperSize")).trim();
        } else if (device != null) {
            Map<String, Object> conn = parseConnection(device.getConnection_json());
            if (conn.get("paperSize") != null) {
                paperSize = String.valueOf(conn.get("paperSize")).trim();
            }
        }
        if (!"80mm".equalsIgnoreCase(paperSize)) {
            paperSize = "58mm";
        }

        int widthMm = "80mm".equalsIgnoreCase(paperSize) ? 80 : 58;
        int widthChars = "80mm".equalsIgnoreCase(paperSize) ? 48 : 32;

        // 2. 门店信息与品牌标头
        String shopName = "老肥油边王";
        if (shopService != null) {
            try {
                Shop s = shopService.getById(shopId);
                if (s != null && !StringUtil.isEmpty(s.getName())) {
                    shopName = s.getName();
                }
            } catch (Exception ignore) {}
        }

        PrintTemplateOptions options = new PrintTemplateOptions();
        options.setPaperWidth(paperSize);
        options.setBrandHeader(shopName);

        // 3. 加载真实业务数据或构建标准 Mock 数据
        Order order = resolvePreviewOrder(shopId, shopName, params);
        boolean isAddDishes = Boolean.parseBoolean(String.valueOf(params.getOrDefault("isAddDishes", false)));

        List<String> rawTickets = new ArrayList<>();
        String scenarioName = "小票预览";

        com.lanf.printing.model.PrintTemplateDsl dynamicDsl = null;
        if (params.get("templateDsl") instanceof Map || params.get("templateDsl") instanceof com.lanf.printing.model.PrintTemplateDsl) {
            dynamicDsl = objectMapper.convertValue(params.get("templateDsl"), com.lanf.printing.model.PrintTemplateDsl.class);
        } else if (params.get("templateJson") != null && StringUtils.hasText(String.valueOf(params.get("templateJson")))) {
            dynamicDsl = printTemplateEngine != null ? printTemplateEngine.parseDsl(String.valueOf(params.get("templateJson"))) : null;
        } else if (params.get("templateId") != null) {
            Long tplId = parseLongSafe(params.get("templateId"));
            if (tplId != null && templateMapper != null) {
                PrintingTemplate pt = templateMapper.selectById(tplId);
                if (pt != null && StringUtils.hasText(pt.getTemplate_json()) && printTemplateEngine != null) {
                    dynamicDsl = printTemplateEngine.parseDsl(pt.getTemplate_json());
                }
            }
        }

        // 若未显式传入模板，从数据库中按场景严格查找已配置模板
        if (dynamicDsl == null && templateMapper != null) {
            String normScenario = PrintScenario.normalizeScenario(scenario);
            PrintingTemplate tpl = null;
            if (shopId > 0) {
                tpl = templateMapper.selectOne(new QueryWrapper<PrintingTemplate>()
                        .eq("shop_id", shopId)
                        .eq("scenario", normScenario)
                        .eq("is_default", 1)
                        .last("LIMIT 1"));
                if (tpl == null) {
                    tpl = templateMapper.selectOne(new QueryWrapper<PrintingTemplate>()
                            .eq("shop_id", shopId)
                            .eq("scenario", normScenario)
                            .orderByDesc("id")
                            .last("LIMIT 1"));
                }
            }
            if (tpl == null) {
                tpl = templateMapper.selectOne(new QueryWrapper<PrintingTemplate>()
                        .eq("shop_id", 0)
                        .eq("scenario", normScenario)
                        .and(w -> w.eq("is_default", 1).or().eq("is_system", 1))
                        .orderByDesc("is_default")
                        .last("LIMIT 1"));
            }
            if (tpl == null) {
                tpl = templateMapper.selectOne(new QueryWrapper<PrintingTemplate>()
                        .eq("shop_id", 0)
                        .eq("scenario", normScenario)
                        .orderByDesc("id")
                        .last("LIMIT 1"));
            }
            if (tpl != null && StringUtils.hasText(tpl.getTemplate_json()) && printTemplateEngine != null) {
                dynamicDsl = printTemplateEngine.parseDsl(tpl.getTemplate_json());
            }
        }

        // 统一严格校验：若数据库中未配置模板且未传入临时 DSL，坚决不回退硬编码，直接报错拦截
        if (dynamicDsl == null) {
            String displayName = PrintScenario.getScenarioDisplayName(scenario);
            throw new ApiException(404, "PRINTING_TEMPLATE_NOT_FOUND", "未配置小票打印模板[场景: " + displayName + "(" + scenario + ")]，请先在模板设计器中配置模板");
        }

        if (printTemplateEngine != null) {
            String norm = PrintScenario.normalizeScenario(scenario);
            scenarioName = PrintScenario.getScenarioDisplayName(norm);

            // 统一组装规则：构建与真实打印完全一致的 PrintContext，
            // 交由 printDispatcherService.renderPreviewContents 走真实打印同一渲染内核
            // （数据准备保留：真实订单优先，缺省 mock 供设计器预览；参数解析保留）
            PrintContext context = new PrintContext();
            context.setShopId(shopId);
            context.setScenario(norm);
            context.setOrder(order);
            context.setAddDishes(isAddDishes);
            if ("EXPEDITE".equals(norm) || "LABEL".equals(norm)) {
                context.setOrderDetail(resolvePreviewDetail(order, params));
            }
            if ("EXPEDITE".equals(norm) && params.get("serveQty") != null) {
                context.setServeQty(Integer.parseInt(String.valueOf(params.get("serveQty"))));
            }
            if ("KITCHEN".equals(norm) && params.get("cidFilter") instanceof List) {
                Set<String> cids = new HashSet<>();
                for (Object o : (List<?>) params.get("cidFilter")) {
                    if (o != null) cids.add(String.valueOf(o).trim());
                }
                context.setCidFilter(cids);
            }
            if ("SHIFT".equals(norm)) {
                context.setShift(resolvePreviewShift(shopId, params));
                if (params.get("statistics") instanceof Map) {
                    context.getExtra().putAll((Map<String, Object>) params.get("statistics"));
                } else {
                    context.getExtra().putAll(mockShiftStats());
                }
            }
            if ("REFUND".equals(norm)) {
                if (params.get("refundInfo") instanceof Map) {
                    context.getExtra().putAll((Map<String, Object>) params.get("refundInfo"));
                } else {
                    context.getExtra().putAll(mockRefundInfo());
                }
            }

            if ("TEST".equals(norm)) {
                // 测试单无业务数据，保留本地组装（testType 参数解析能力）
                String testType = params.get("testType") != null ? String.valueOf(params.get("testType")) : "STANDARD_RECEIPT";
                String devName = device != null ? device.getName() : "测试打印机";
                String transport = device != null ? device.getTransport() : "CLOUD";
                String brand = device != null ? device.getBrand() : "飞鹅";
                String test = printTemplateEngine.renderDynamicTestTicket(dynamicDsl, testType, devName, transport, brand, shopId);
                if (StringUtils.hasText(test)) rawTickets.add(test);
            } else if (printDispatcherService != null) {
                try {
                    List<com.lanf.printing.model.PrintResolvedPreview> sources = printDispatcherService.renderPreviewContents(
                            shopId, norm, context, dynamicDsl, null, deviceId);
                    for (com.lanf.printing.model.PrintResolvedPreview source : sources) {
                        if (source.getContents() != null) {
                            rawTickets.addAll(source.getContents());
                        }
                    }
                } catch (IllegalArgumentException ex) {
                    throw new ApiException(404, "PRINTING_PREVIEW_TARGET_NOT_FOUND", ex.getMessage());
                } catch (IllegalStateException ex) {
                    throw new ApiException(409, "PRINTING_PREVIEW_RENDER_FAILED", ex.getMessage());
                }
            } else {
                throw new ApiException(500, "PRINTING_DISPATCHER_UNAVAILABLE", "打印调度服务未就绪，无法按统一规则渲染预览");
            }
        }

        // 支持 customContent 覆盖（与真实打印 dispatch 语义一致：直出，跳过模板与规则）
        if (params.get("customContent") != null && StringUtils.hasText(String.valueOf(params.get("customContent")))) {
            rawTickets.clear();
            rawTickets.add(String.valueOf(params.get("customContent")));
        }

        // 4. 解析每张小票
        List<PrintPreviewResult.TicketPreviewItem> ticketItems = new ArrayList<>();
        StringBuilder combinedRaw = new StringBuilder();

        for (int i = 0; i < rawTickets.size(); i++) {
            String raw = rawTickets.get(i);
            String plain = PrintTicketParser.toPlainText(raw);
            List<PrintPreviewResult.PrintPreviewElement> elements = PrintTicketParser.parseElements(raw);

            String ticketTitle = scenarioName;
            if (rawTickets.size() > 1) {
                ticketTitle += " (" + (i + 1) + "/" + rawTickets.size() + ")";
            }

            ticketItems.add(new PrintPreviewResult.TicketPreviewItem(i, ticketTitle, raw, plain, elements));
            if (i > 0) combinedRaw.append("\n<CUT>\n");
            combinedRaw.append(raw);
        }

        // 5. 组装结果
        PrintPreviewResult result = new PrintPreviewResult();
        result.setScenario(scenario);
        result.setScenarioName(scenarioName);
        result.setPaperSize(paperSize);
        result.setPaperWidthMm(widthMm);
        result.setPaperWidthChars(widthChars);
        result.setShopName(shopName);
        result.setTickets(ticketItems);
        result.setRawCombinedContent(combinedRaw.toString());
        result.setRenderedAt(iso(LocalDateTime.now(ZONE)));
        return result;
    }

    /**
     * 事实预览：拒绝样例订单，只允许已落库的订单（交接班场景允许 shiftId）。
     * 渲染仍复用 previewPrint 的 DSL 引擎，保证 rawContent/AST 来自同一原生内容。
     */
    public PrintPreviewResult previewExact(int shopId, Map<String, Object> params) {
        if (params == null) params = new LinkedHashMap<>();
        String scenario = String.valueOf(params.getOrDefault("scenario", "ORDER"));
        String normalized = PrintScenario.normalizeScenario(scenario);
        boolean shiftScenario = "SHIFT".equalsIgnoreCase(normalized);
        if (!shiftScenario && params.get("orderId") == null && params.get("order_id") == null && params.get("orderNo") == null) {
            throw new ApiException(400, "PRINTING_EXACT_ORDER_REQUIRED", "精确预览必须提供真实订单 orderId 或 orderNo");
        }
        if (shiftScenario && params.get("shiftId") == null && params.get("shift_id") == null) {
            throw new ApiException(400, "PRINTING_EXACT_SHIFT_REQUIRED", "交接班精确预览必须提供真实 shiftId");
        }
        if ("TEST".equals(normalized) || params.containsKey("customContent") || params.containsKey("templateDsl")
                || params.containsKey("templateJson") || params.containsKey("templateId") || params.containsKey("statistics")
                || params.containsKey("refundInfo") || params.containsKey("contextOverrides")) {
            throw new ApiException(400, "PRINTING_EXACT_OVERRIDE_FORBIDDEN", "精确预览不接受样例或人工业务数据覆盖");
        }
        if (printDispatcherService == null) throw new ApiException(500, "PRINTING_DISPATCHER_UNAVAILABLE", "打印调度服务未就绪");
        PrintContext context = new PrintContext(); context.setShopId(shopId); context.setScenario(normalized);
        Order order = null;
        if (shiftScenario) {
            Long shiftId = parseLongSafe(params.get("shiftId") != null ? params.get("shiftId") : params.get("shift_id"));
            Shift shift = shiftService == null || shiftId == null ? null : shiftService.getById(shiftId);
            if (shift == null) throw new ApiException(404, "PRINTING_EXACT_SHIFT_NOT_FOUND", "班次不存在");
            if (!Integer.valueOf(shopId).equals(shift.getShop_id())) throw new ApiException(403, "SHIFT_FORBIDDEN", "班次不属于当前门店");
            context.setShift(shift); context.getExtra().put("orderCount", shift.getOrder_count()); context.getExtra().put("totalAmount", shift.getTotal_amount());
        } else {
            order = resolveExactOrder(shopId, params); context.setOrder(order);
            context.setAddDishes(Boolean.parseBoolean(String.valueOf(params.getOrDefault("isAddDishes", false))));
            if ("CHECKOUT".equals(normalized)) {
                if (!"success".equalsIgnoreCase(order.getTransac_status())) {
                    throw new ApiException(400, "ORDER_NOT_CHECKED_OUT", "订单尚未结账，不能打印结账单，未结账订单只能打印预结单");
                }
            }
            if ("EXPEDITE".equals(normalized) || "LABEL".equals(normalized)) context.setOrderDetail(resolveExactDetail(order, params));
            if ("EXPEDITE".equals(normalized)) { Integer qty = parseIntSafe(params.get("serveQty")); if (qty == null || qty < 1) throw new ApiException(400, "PRINTING_EXACT_SERVE_QTY_INVALID", "serveQty 必须大于 0"); context.setServeQty(qty); }
            if ("KITCHEN".equals(normalized) && params.get("cidFilter") instanceof List) { Set<String> cids = new HashSet<>(); for (Object item : (List<?>) params.get("cidFilter")) if (item != null) cids.add(String.valueOf(item)); context.setCidFilter(cids); }
            if ("REFUND".equals(normalized)) { if (order.getRefund_amount() == null || order.getRefund_amount() <= 0) throw new ApiException(409, "PRINTING_EXACT_REFUND_REQUIRED", "订单没有真实退款数据"); context.getExtra().put("refundAmount", order.getRefund_amount()); }
        }
        List<PrintResolvedPreview> sources;
        try { sources = printDispatcherService.previewExact(shopId, normalized, context, parseLongSafe(params.get("ruleId")), parseLongSafe(params.get("deviceId"))); }
        catch (IllegalArgumentException ex) { throw new ApiException(404, "PRINTING_EXACT_TARGET_NOT_FOUND", ex.getMessage()); }
        catch (IllegalStateException ex) { throw new ApiException(409, "PRINTING_EXACT_RENDER_FAILED", ex.getMessage()); }
        PrintPreviewResult result = new PrintPreviewResult(); result.setScenario(PrintScenario.resolveDispatchCode(normalized, context)); result.setScenarioName(PrintScenario.getScenarioDisplayName(normalized));
        List<PrintPreviewResult.TicketPreviewItem> tickets = new ArrayList<>(); StringBuilder combined = new StringBuilder(); int index = 0;
        for (PrintResolvedPreview source : sources) for (String raw : source.getContents()) {
            PrintPreviewResult.TicketPreviewItem ticket = new PrintPreviewResult.TicketPreviewItem(index++, result.getScenarioName(), raw, PrintTicketParser.toPlainText(raw), PrintTicketParser.parseElements(raw));
            ticket.setRuleId(source.getRuleId()); ticket.setDeviceId(source.getDeviceId()); ticket.setDeviceName(source.getDeviceName()); ticket.setTemplateId(source.getTemplateId()); ticket.setTemplateCode(source.getTemplateCode()); tickets.add(ticket);
            if (combined.length() > 0) combined.append("\n<CUT>\n"); combined.append(raw);
        }
        result.setTickets(tickets); result.setRawCombinedContent(combined.toString()); result.setRenderedAt(iso(LocalDateTime.now(ZONE))); return result;
    }

    private Order resolveExactOrder(int shopId, Map<String, Object> params) {
        Object rawId = params.get("orderId") != null ? params.get("orderId") : params.get("order_id"); Object rawNo = params.get("orderNo") != null ? params.get("orderNo") : params.get("order_no");
        Order order = null; Long id = parseLongSafe(rawId);
        if (orderService != null && id != null) order = orderService.getById(id.intValue());
        if (order == null && orderService != null && rawNo != null) order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", String.valueOf(rawNo).trim()).eq("shop_id", shopId).last("LIMIT 1"));
        if (order == null) throw new ApiException(404, "PRINTING_EXACT_ORDER_NOT_FOUND", "订单不存在");
        if (!Integer.valueOf(shopId).equals(order.getShop_id())) throw new ApiException(403, "ORDER_FORBIDDEN", "订单不属于当前门店");
        List<OrderDetail> details = orderDetailService == null ? Collections.emptyList() : orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        if (details == null || details.isEmpty()) throw new ApiException(409, "PRINTING_EXACT_ORDER_DETAILS_REQUIRED", "订单没有可打印的真实明细"); order.setGoods_list(details); return order;
    }
    private OrderDetail resolveExactDetail(Order order, Map<String, Object> params) {
        Long id = parseLongSafe(params.get("detailId")); if (id == null) throw new ApiException(400, "PRINTING_EXACT_DETAIL_REQUIRED", "该场景必须提供真实 detailId");
        for (OrderDetail detail : order.getGoods_list()) if (detail.getId() != null && id.longValue() == detail.getId().longValue()) return detail;
        throw new ApiException(404, "PRINTING_EXACT_DETAIL_NOT_FOUND", "菜品明细不属于该订单");
    }

    private Order resolvePreviewOrder(int shopId, String shopName, Map<String, Object> params) {
        Object rawOrderId = params.get("orderId");
        if (rawOrderId == null) {
            rawOrderId = params.get("order_id");
        }
        Object rawOrderNo = params.get("orderNo");
        if (rawOrderNo == null) {
            rawOrderNo = params.get("order_no");
        }

        if (orderService != null && (rawOrderId != null || rawOrderNo != null)) {
            try {
                Order found = null;
                if (rawOrderId != null) {
                    Long oid = parseLongSafe(rawOrderId);
                    if (oid != null) {
                        found = orderService.getById(oid.intValue());
                    }
                } else {
                    found = orderService.getOne(new QueryWrapper<Order>()
                            .eq("order_no", String.valueOf(rawOrderNo).trim())
                            .eq("shop_id", shopId));
                }
                if (found != null) {
                    if (found.getShop_id() != null && found.getShop_id() != shopId) {
                        throw new ApiException(403, "ORDER_FORBIDDEN", "订单不属于当前门店");
                    }
                    if (orderDetailService != null) {
                        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>()
                                .eq("mId", found.getId()));
                        if (details == null || details.isEmpty()) {
                            details = orderDetailService.list(new QueryWrapper<OrderDetail>()
                                    .eq("Morder_no", found.getOrder_no()));
                        }
                        if (details != null && !details.isEmpty()) {
                            found.setGoods_list(details);
                        } else {
                            throw new ApiException(409, "PRINTING_PREVIEW_ORDER_DETAILS_REQUIRED", "订单没有可打印的真实明细，请核对订单数据");
                        }
                    }
                    return found;
                }
            } catch (ApiException ae) {
                throw ae;
            } catch (Exception e) {
                log.warn("[printing] preview load order error: {}", e.getMessage());
            }
        }

        return buildMockOrder(shopId, shopName);
    }

    private Order buildMockOrder(int shopId, String shopName) {
        Order o = new Order();
        o.setId(9999);
        o.setShop_id(shopId);
        o.setOrder_no("DD" + DateTimeFormatter.ofPattern("yyyyMMddHHmmss").format(LocalDateTime.now(ZONE)) + "001");
        o.setTable_number("8号桌");
        o.setDineInOrTakeOut("DineIn");
        o.setNumber_of_diners("4");
        o.setSett_amount(128.00);
        o.setDiscount_amount(0.00);
        o.setService_fee(0.00);
        o.setRefund_amount(0.00);
        o.setTransac_status("success");
        o.setPay_time(new Date());
        o.setOrder_time(new Date());

        List<OrderDetail> items = new ArrayList<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(1001);
        d1.setMId(9999);
        d1.setName("炭烤羊肉串(10串)");
        d1.setCid("1");
        d1.setQuantity("2");
        d1.setTotal_price(60.00);
        d1.setSelectedSpicy("微辣");
        items.add(d1);

        OrderDetail d2 = new OrderDetail();
        d2.setId(1002);
        d2.setMId(9999);
        d2.setName("招牌烤油边(大份)");
        d2.setCid("1");
        d2.setQuantity("1");
        d2.setTotal_price(48.00);
        d2.setSelectedSpicy("原味");
        items.add(d2);

        OrderDetail d3 = new OrderDetail();
        d3.setId(1003);
        d3.setMId(9999);
        d3.setName("精酿原浆鲜啤");
        d3.setCid("4");
        d3.setQuantity("2");
        d3.setTotal_price(20.00);
        items.add(d3);

        o.setGoods_list(items);
        return o;
    }

    private OrderDetail resolvePreviewDetail(Order order, Map<String, Object> params) {
        if (order != null && order.getGoods_list() != null && !order.getGoods_list().isEmpty()) {
            Long detailId = params.get("detailId") != null ? parseLongSafe(params.get("detailId")) : null;
            if (detailId != null) {
                for (OrderDetail d : order.getGoods_list()) {
                    if (d.getId() != null && d.getId().longValue() == detailId.longValue()) {
                        return d;
                    }
                }
            }
            return order.getGoods_list().get(0);
        }
        OrderDetail d = new OrderDetail();
        d.setId(5001);
        d.setName("招牌烤油边(大份)");
        d.setQuantity("1");
        d.setTotal_price(48.00);
        return d;
    }

    private Shift resolvePreviewShift(int shopId, Map<String, Object> params) {
        Shift s = new Shift();
        s.setId(101L);
        s.setShop_id(shopId);
        s.setAdmin_id(1);
        s.setStart_time(new Date(System.currentTimeMillis() - 8 * 3600 * 1000));
        s.setEnd_time(new Date());
        s.setTotal_amount(BigDecimal.valueOf(2580.00));
        s.setStart_cash(BigDecimal.valueOf(300.00));
        s.setEnd_cash(BigDecimal.valueOf(620.00));
        s.setOrder_count(42);
        return s;
    }

    private Map<String, Object> mockShiftStats() {
        Map<String, Object> stats = new LinkedHashMap<>();
        stats.put("wechatAmount", 1680.00);
        stats.put("alipayAmount", 580.00);
        stats.put("cashAmount", 320.00);
        stats.put("memberAmount", 0.00);
        stats.put("totalRefund", 68.00);
        stats.put("discountAmount", 120.00);
        return stats;
    }

    private Map<String, Object> mockRefundInfo() {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("refundNo", "TK" + System.currentTimeMillis());
        r.put("refundAmount", 48.00);
        r.put("refundReason", "菜品估清退款");
        r.put("operator", "管理员");
        r.put("refundTime", LocalDateTime.now(ZONE).format(DATETIME));
        return r;
    }

    private static Long parseLongSafe(Object o) {
        if (o == null) return null;
        try {
            return Long.parseLong(String.valueOf(o).trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer parseIntSafe(Object o) {
        if (o == null) return null;
        try {
            return Integer.parseInt(String.valueOf(o).trim());
        } catch (Exception e) {
            return null;
        }
    }

    private String iso(LocalDateTime time) {
        return time == null ? null : time.atZone(ZONE).format(ISO);
    }
}
