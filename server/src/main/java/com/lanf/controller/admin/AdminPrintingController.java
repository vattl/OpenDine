package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.common.PageResult;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.printing.service.PrintingService;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 打印模块管理端接口（协调文档 §2 打印相关行）：
 * <ul>
 *   <li>GET  /admin/printing/devices          设备列表（transport/status 筛选 + 分页，connection 脱敏）</li>
 *   <li>POST /admin/printing/devices          新建设备（凭据不明文回传）</li>
 *   <li>PUT  /admin/printing/devices/{id}     更新设备（version 乐观锁，冲突 409 PRINTING_VERSION_CONFLICT）</li>
 *   <li>GET  /admin/printing/rules            打印规则列表</li>
 *   <li>PUT  /admin/printing/rules            规则列表整体保存（version 乐观锁）</li>
 *   <li>POST /admin/printing/devices/{id}/test 打印测试（CLOUD 走服务端飞鹅，其余端侧执行）</li>
 *   <li>GET  /admin/printing/jobs             打印任务记录（时间/设备/状态筛选 + 分页）</li>
 * </ul>
 * 鉴权/门店上下文由 SysInterceptor 统一处理；不提供任何「远程重启打印服务」能力。
 */
@RestController
@RequestMapping("/admin/printing")
public class AdminPrintingController {

    @Autowired
    private PrintingService printingService;
    @Autowired(required = false)
    private com.lanf.printing.service.PrintDispatcherService printDispatcherService;
    @Autowired(required = false)
    private com.lanf.printing.service.UnifiedPrintService unifiedPrintService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /** 打印设备列表：类型、状态、分页（connection 中密钥/序列号脱敏） */
    @GetMapping("/devices")
    public R listDevices(@RequestParam(required = false) String transport,
                         @RequestParam(required = false) String status,
                         @RequestParam(defaultValue = "1") int page,
                         @RequestParam(defaultValue = "20") int pageSize) {
        int shopId = requireShopId();
        PageResult pr = printingService.listDevices(shopId, transport, status, page, pageSize);
        R r = new R();
        r.put("shopId", shopId);
        putPage(r, pr);

        Map<String, Object> data = new java.util.LinkedHashMap<>();
        data.put("page", pr.getPage());
        data.put("pageSize", pr.getPageSize());
        data.put("total", pr.getTotal());
        data.put("source", "SHOP");
        data.put("items", pr.getItems());
        r.put("data", data);
        return r;
    }

    /** 打印设备详情：单设备全量字段，凭据脱敏 */
    @GetMapping("/devices/{id}")
    public R getDeviceDetail(@PathVariable("id") long id) {
        int shopId = requireShopId();
        Map<String, Object> device = printingService.getDeviceDetail(shopId, id);
        R r = new R();
        r.put("device", device);
        r.put("data", device);
        return r;
    }

    /** 新建设备：返回 device（含脱敏后 connection）+ version */
    @PostMapping("/devices")
    public R createDevice(@RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> device = printingService.createDevice(shopId, body, currentAdminId());
        audit("create_device", String.valueOf(device.get("id")), device);
        R r = new R();
        r.put("device", device);
        r.put("data", device);
        r.put("version", device.get("version"));
        return r;
    }

    /** 更新设备：version 乐观锁；冲突 409 PRINTING_VERSION_CONFLICT + 最新摘要 */
    @PutMapping("/devices/{id}")
    public R updateDevice(@PathVariable("id") long id, @RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> device = printingService.updateDevice(shopId, id, body, currentAdminId());
        audit("update_device", String.valueOf(id), device);
        R r = new R();
        r.put("device", device);
        r.put("data", device);
        r.put("version", device.get("version"));
        return r;
    }

    /** 删除设备：校验是否被出票规则引用，若引用则阻断 */
    @org.springframework.web.bind.annotation.DeleteMapping("/devices/{id}")
    public R deleteDevice(@PathVariable("id") long id) {
        int shopId = requireShopId();
        printingService.deleteDevice(shopId, id);
        audit("delete_device", String.valueOf(id), null);
        return R.ok("删除打印设备成功");
    }

    /** 打印设备实时状态探活 */
    @GetMapping("/devices/{id}/status")
    public R probeDeviceStatus(@PathVariable("id") long id) {
        int shopId = requireShopId();
        Map<String, Object> status = printingService.probeDeviceStatus(shopId, id);
        R r = new R();
        r.putAll(status);
        r.put("data", status);
        return r;
    }

    /** 清空云打印机待打印队列 */
    @PostMapping("/devices/{id}/clear-queue")
    public R clearDeviceQueue(@PathVariable("id") long id) {
        int shopId = requireShopId();
        Map<String, Object> result = printingService.clearDeviceQueue(shopId, id, currentAdminId());
        audit("clear_printer_queue", String.valueOf(id), result);
        R r = new R();
        r.putAll(result);
        r.put("data", result);
        return r;
    }

    /** 打印小票实时预览 (POST)：按场景、订单、设备规格组装小票数据并返回结构化节点树 */
    @PostMapping("/preview")
    public R previewPrintPost(@RequestBody(required = false) Map<String, Object> body) {
        int shopId = requireShopId();
        com.lanf.printing.model.PrintPreviewResult result = printingService.previewPrint(shopId, body);
        R r = new R();
        r.put("msg", "预览生成成功");
        r.put("data", result);
        return r;
    }

    /** 精确预览：只使用真实订单/门店数据，不发送打印任务。 */
    @PostMapping("/preview/exact")
    public R previewExact(@RequestBody(required = false) Map<String, Object> body) {
        int shopId = requireShopId();
        com.lanf.printing.model.PrintPreviewResult result = printingService.previewExact(shopId, body);
        R r = new R();
        r.put("msg", "精确预览生成成功");
        r.put("data", result);
        return r;
    }

    /** 统一出票与补打调度接口 */
    @PostMapping("/dispatch")
    public R dispatch(@RequestBody com.lanf.printing.model.UnifiedPrintRequest request) {
        int shopId = requireShopId();
        if (unifiedPrintService == null) {
            throw new ApiException(500, "PRINTING_SERVICE_UNAVAILABLE", "统一打印服务未就绪");
        }
        com.lanf.printing.model.UnifiedPrintResponse resp = unifiedPrintService.dispatch(request, currentAdminId(), shopId);
        audit("dispatch_print", resp.getOrderNo() != null ? resp.getOrderNo() : resp.getScenario(), null);
        R r = R.ok(resp.getSummary());
        r.put("data", resp);
        return r;
    }

    /** 打印小票实时预览 (GET)：支持 Query 参数快速预览 */
    @GetMapping("/preview")
    public R previewPrintGet(@RequestParam(required = false) String scenario,
                             @RequestParam(required = false) Long orderId,
                             @RequestParam(required = false) String orderNo,
                             @RequestParam(required = false) Long deviceId,
                             @RequestParam(required = false) String paperSize,
                             @RequestParam(required = false) Boolean isAddDishes) {
        int shopId = requireShopId();
        Map<String, Object> params = new java.util.LinkedHashMap<>();
        if (scenario != null) params.put("scenario", scenario);
        if (orderId != null) params.put("orderId", orderId);
        if (orderNo != null) params.put("orderNo", orderNo);
        if (deviceId != null) params.put("deviceId", deviceId);
        if (paperSize != null) params.put("paperSize", paperSize);
        if (isAddDishes != null) params.put("isAddDishes", isAddDishes);

        com.lanf.printing.model.PrintPreviewResult result = printingService.previewPrint(shopId, params);
        R r = new R();
        r.put("msg", "预览生成成功");
        r.put("data", result);
        return r;
    }

    /** 打印规则列表：场景、设备、模板、份数 + 整体版本 */
    @GetMapping("/rules")
    public R getRules() {
        int shopId = requireShopId();
        Map<String, Object> rules = printingService.getRules(shopId);
        R r = new R();
        r.putAll(rules);
        r.put("data", rules);
        return r;
    }

    /** 打印规则整体保存：{version, rules:[...]}；冲突 409 */
    @PutMapping("/rules")
    public R saveRules(@RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> result = printingService.saveRules(shopId, body, currentAdminId());
        audit("save_rules", "shop:" + shopId, result);
        R r = new R();
        r.putAll(result);
        r.put("data", result);
        return r;
    }

    /** 打印测试：入参 testType（如 order/refund/STANDARD_RECEIPT/CUTTER_TEST）与 customContent，返回 {jobId, status, executor} */
    @PostMapping("/devices/{id}/test")
    public R testDevice(@PathVariable("id") long id,
                        @RequestBody(required = false) Map<String, Object> body) {
        int shopId = requireShopId();
        String testType = body == null || body.get("testType") == null
                ? null : String.valueOf(body.get("testType"));
        String customContent = body == null || body.get("customContent") == null
                ? null : String.valueOf(body.get("customContent"));
        Map<String, Object> job = printingService.createTestJob(shopId, id, testType, customContent, currentAdminId());
        audit("print_test", String.valueOf(id), job);
        R r = new R();
        r.put("msg", job.get("message") != null ? job.get("message") : "测试出票指令已下发");
        r.put("device", id);
        r.put("jobId", job.get("jobId"));
        r.put("status", job.get("status"));
        r.put("executor", job.get("executor"));
        r.put("data", job);
        return r;
    }

    /** 打印任务记录：时间范围、设备、状态筛选 + 分页（含错误与重试信息） */
    @GetMapping("/jobs")
    public R listJobs(@RequestParam(required = false) String status,
                      @RequestParam(required = false) Long deviceId,
                      @RequestParam(required = false) String startTime,
                      @RequestParam(required = false) String endTime,
                      @RequestParam(defaultValue = "1") int page,
                      @RequestParam(defaultValue = "20") int pageSize) {
        int shopId = requireShopId();
        PageResult pr = printingService.listJobs(shopId, status, deviceId, startTime, endTime, page, pageSize);
        R r = new R();
        r.put("shopId", shopId);
        putPage(r, pr);

        Map<String, Object> data = new java.util.LinkedHashMap<>();
        data.put("page", pr.getPage());
        data.put("pageSize", pr.getPageSize());
        data.put("total", pr.getTotal());
        data.put("items", pr.getItems());
        r.put("data", data);
        return r;
    }

    /** 打印任务重试/补打：重新下发打印任务 */
    @PostMapping("/jobs/{id}/reprint")
    public R reprintJob(@PathVariable("id") long id) {
        requireShopId();
        if (printDispatcherService == null) {
            return R.error("打印调度引擎未就绪");
        }
        com.lanf.printing.model.PrintDispatchResult result = printDispatcherService.reprintJob(id, currentAdminId());
        audit("reprint_job", String.valueOf(id), null);
        if (!result.isSuccess()) {
            return R.error(result.getError() != null ? result.getError() : "补打指令下发失败");
        }
        R r = new R();
        r.put("msg", result.getMessage());
        r.put("jobId", result.getJobId());
        r.put("status", result.getStatus());
        r.put("data", result);
        return r;
    }

    // ---------------- 模板管理 (C004) ----------------

    /** 模板设计器元数据（全场景列表、参数绑定字典、积木块定义） */
    @GetMapping("/templates/meta")
    public R getTemplateMeta() {
        Map<String, Object> meta = printingService.getTemplateMeta();
        R r = new R();
        r.put("code", 0);
        r.put("msg", "success");
        r.put("meta", meta);
        r.put("data", meta);
        return r;
    }

    /** 打印模板列表（支持 scenario / paperSize 筛选，包含系统内置与自定义模板） */
    @GetMapping("/templates")
    public R listTemplates(@RequestParam(required = false) String scenario,
                           @RequestParam(required = false) String paperSize) {
        int shopId = requireShopId();
        java.util.List<Map<String, Object>> templates = printingService.getTemplates(shopId, scenario, paperSize);
        R r = new R();
        r.put("shopId", shopId);
        r.put("templates", templates);
        r.put("data", templates);
        return r;
    }

    /** 打印模板详情（含完整排版 JSON DSL 配置） */
    @GetMapping("/templates/{id}")
    public R getTemplateDetail(@PathVariable("id") long id) {
        int shopId = requireShopId();
        Map<String, Object> template = printingService.getTemplateById(shopId, id);
        R r = new R();
        r.put("template", template);
        r.put("data", template);
        return r;
    }

    /** 新建自定义打印模板 */
    @PostMapping("/templates")
    public R createTemplate(@RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> template = printingService.createTemplate(shopId, body, currentAdminId());
        audit("create_template", String.valueOf(template.get("id")), template);
        R r = new R();
        r.put("template", template);
        r.put("data", template);
        r.put("version", template.get("version"));
        return r;
    }

    /** 更新自定义打印模板（version 乐观锁，冲突 409 PRINTING_VERSION_CONFLICT） */
    @PutMapping("/templates/{id}")
    public R updateTemplate(@PathVariable("id") long id, @RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> template = printingService.updateTemplate(shopId, id, body, currentAdminId());
        audit("update_template", String.valueOf(id), template);
        R r = new R();
        r.put("template", template);
        r.put("data", template);
        r.put("version", template.get("version"));
        return r;
    }

    /** 删除自定义打印模板（系统模板/被出票规则引用的模板拦截删除） */
    @org.springframework.web.bind.annotation.DeleteMapping("/templates/{id}")
    public R deleteTemplate(@PathVariable("id") long id) {
        int shopId = requireShopId();
        printingService.deleteTemplate(shopId, id, currentAdminId());
        audit("delete_template", String.valueOf(id), null);
        R r = new R();
        r.put("msg", "模板删除成功");
        r.put("id", id);
        return r;
    }

    /** 设为场景默认打印模板 */
    @PostMapping("/templates/{id}/set-default")
    public R setDefaultTemplate(@PathVariable("id") long id) {
        int shopId = requireShopId();
        Map<String, Object> template = printingService.setDefaultTemplate(shopId, id, currentAdminId());
        audit("set_default_template", String.valueOf(id), template);
        R r = new R();
        r.put("msg", "已设为默认模板");
        r.put("template", template);
        r.put("data", template);
        return r;
    }

    // ---------------- 工具 ----------------

    private void putPage(R r, PageResult pr) {
        r.put("page", pr.getPage());
        r.put("pageSize", pr.getPageSize());
        r.put("total", pr.getTotal());
        r.put("items", pr.getItems());
    }

    private int requireShopId() {
        Object shopId = currentRequest.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        if (!(shopId instanceof Integer)) {
            throw new ApiException(4001, "SHOP_CONTEXT_MISSING", "缺少门店上下文，请传 X-Shop-Id");
        }
        return (Integer) shopId;
    }

    private Integer currentAdminId() {
        Object adminId = currentRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return adminId instanceof Integer ? (Integer) adminId : null;
    }

    /** 写操作审计（失败不阻断业务） */
    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        try {
            securityAuditService.recordPrivilegedAction(currentRequest, requireShopId(),
                    "printing", action, targetId, currentAdminId(), snapshot, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
