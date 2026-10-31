package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.adminlog.service.AdminLogService;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 日志查询 / 归档检索 / 日志导出（协调文档 §2、§4、§5）。
 * 权限（拦截器层 t_api_permission 控制）：
 * - GET  /admin/logs → log:view（近 30 天在线查询，内容脱敏）
 * - POST /admin/logs/archive-search → log:archive（门店角色可授，异步 202 语义）
 * - GET  /admin/logs/archive-search/{jobId} → log:view|log:archive
 * - POST /admin/logs/exports → log:export（仅授 super_admin，purpose 必填）
 */
@RestController
@RequestMapping("/admin/logs")
public class AdminLogController {

    @Autowired
    private AdminLogService adminLogService;
    @Autowired
    private AdminShopScopeGuard adminShopScopeGuard;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /**
     * 日志查询：type(module)/操作者/时间筛选 + 分页；仅返回近 30 天，
     * 时间越界直接空页并附 hint；日志内容脱敏（手机号/身份证号）。
     */
    @GetMapping
    public R listLogs(@RequestParam(required = false) String type,
                      @RequestParam(required = false) String module,
                      @RequestParam(required = false) String action,
                      @RequestParam(required = false) Integer operator,
                      @RequestParam(required = false) Integer shopId,
                      @RequestParam(required = false) Boolean allShops,
                      @RequestParam(required = false) String startTime,
                      @RequestParam(required = false) String endTime,
                      @RequestParam(required = false, defaultValue = "business") String category,
                      @RequestParam(required = false, defaultValue = "1") int page,
                      @RequestParam(required = false, defaultValue = "20") int pageSize) {
        // 门店范围口径与 AdminOperationLogController 一致（target 0 = 全局）
        int[] target = new int[1];
        if (Boolean.TRUE.equals(allShops)) {
            R scopeError = adminShopScopeGuard.requireHeadquarters();
            if (scopeError != null) {
                return scopeError;
            }
            target[0] = 0;
        } else {
            R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
            if (scopeError != null) {
                return scopeError;
            }
        }
        String moduleFilter = type != null && !type.trim().isEmpty() ? type.trim() : module;
        Map<String, Object> result = adminLogService.queryLogs(
                target[0], moduleFilter, action, operator, startTime, endTime, page, pageSize, category);
        R r = new R();
        r.putAll(result);
        return r;
    }

    /**
     * 归档日志检索（30 天 ~ 1 年，异步）：{conditions…} → {jobId, status:"PENDING", code:"ARCHIVE_QUERY_PENDING"}。
     * 完成后 result_summary_json 存命中数；超过 365 天的数据按 1 年销毁策略不再返回。
     */
    @PostMapping("/archive-search")
    public R archiveSearch(@RequestBody(required = false) Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> result = adminLogService.createArchiveSearch(shopId, currentAdminId(), body);
        audit("archive_search", "job:" + result.get("jobId"), body);
        R r = new R();
        r.putAll(result);
        return r;
    }

    /** 归档检索任务状态查询：DONE 时附命中数与「结果请至归档存储查看」提示 */
    @GetMapping("/archive-search/{jobId}")
    public R archiveSearchJob(@PathVariable Long jobId) {
        int shopId = requireShopId();
        Map<String, Object> result = adminLogService.getArchiveSearchJob(shopId, jobId);
        R r = new R();
        r.putAll(result);
        return r;
    }

    /**
     * 日志导出（仅超管：log:export 在拦截器层控制）：{query…, purpose 必填}；
     * purpose 缺失 400（LOG_EXPORT_PURPOSE_REQUIRED）；同步生成近 1 年 CSV；返回 {jobId, auditNo}。
     */
    @PostMapping("/exports")
    public R exportLogs(@RequestBody(required = false) Map<String, Object> body) {
        int shopId = requireShopId();
        Map<String, Object> b = body == null ? new LinkedHashMap<>() : body;
        String purpose = b.get("purpose") == null ? null : String.valueOf(b.get("purpose"));
        Map<String, Object> query = b.get("query") instanceof Map
                ? (Map<String, Object>) b.get("query")
                : new LinkedHashMap<>();
        Map<String, Object> result = adminLogService.createLogExport(shopId, currentAdminId(), query, purpose);
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("purpose", purpose == null ? null : purpose.trim());
        audit("log_export", "job:" + result.get("jobId") + ";auditNo:" + result.get("auditNo"), snapshot);
        R r = new R();
        r.putAll(result);
        return r;
    }

    // ---------------- 工具 ----------------

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
                    "log", action, targetId, currentAdminId(), snapshot, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
