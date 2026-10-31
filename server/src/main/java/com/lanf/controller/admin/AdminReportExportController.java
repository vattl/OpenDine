package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.report.service.ReportExportService;
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
import javax.servlet.http.HttpServletResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 报表导出任务（协调文档 §2「报表导出任务」：异步生成、地址短期有效）。
 * 权限：POST 需 report:export（仅超级管理员）；GET 列表/下载 report:view|report:export
 * （由 t_api_permission + SysInterceptor 拦截器层统一控制）。
 */
@RestController
@RequestMapping("/admin/reports/exports")
public class AdminReportExportController {

    @Autowired
    private ReportExportService reportExportService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /** 创建报表导出任务（PENDING，异步生成）：{reportType, filters, format} → {jobId, status} */
    @PostMapping
    public R createExport(@RequestBody Map<String, Object> body) {
        int shopId = requireShopId();
        String reportType = body.get("reportType") == null ? null : String.valueOf(body.get("reportType"));
        String format = body.get("format") == null ? null : String.valueOf(body.get("format"));
        Map<String, Object> filters = body.get("filters") instanceof Map
                ? (Map<String, Object>) body.get("filters")
                : new LinkedHashMap<>();
        Map<String, Object> result = reportExportService.createReportExportJob(
                shopId, currentAdminId(), reportType, filters, format);
        audit("create_export", "job:" + result.get("jobId"), result);
        R r = new R();
        r.putAll(result);
        return r;
    }

    /** 任务列表 + 分页；DONE 且 token 未过期附 downloadUrl，过期则 downloadUrl=null + error */
    @GetMapping
    public R listExports(@RequestParam(required = false, defaultValue = "1") int page,
                         @RequestParam(required = false, defaultValue = "20") int pageSize,
                         @RequestParam(required = false) String jobType,
                         @RequestParam(required = false) String status) {
        int shopId = requireShopId();
        Map<String, Object> result = reportExportService.listJobs(shopId, page, pageSize, jobType, status);
        R r = new R();
        r.putAll(result);
        return r;
    }

    /** 下载导出文件：校验 token 与 15 分钟有效期，Content-Disposition 输出 */
    @GetMapping("/{id}/download")
    public void download(@PathVariable("id") Long id,
                         @RequestParam(required = false) String token,
                         HttpServletResponse response) throws Exception {
        int shopId = requireShopId();
        Path file = reportExportService.resolveDownload(shopId, id, token);
        String fileName = file.getFileName().toString();
        response.setContentType("text/csv;charset=UTF-8");
        String encoded = java.net.URLEncoder.encode(fileName, "UTF-8").replace("+", "%20");
        response.setHeader("Content-Disposition",
                "attachment; filename=\"" + fileName + "\"; filename*=UTF-8''" + encoded);
        response.setContentLengthLong(Files.size(file));
        Files.copy(file, response.getOutputStream());
        response.getOutputStream().flush();
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
                    "report", action, targetId, currentAdminId(), snapshot, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
