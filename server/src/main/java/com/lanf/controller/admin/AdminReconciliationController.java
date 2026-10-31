package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.ChannelStatementBatch;
import com.lanf.entity.R;
import com.lanf.entity.ReconciliationCase;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IReconciliationService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;

/**
 * 渠道对账与差异处理控制器 (POS-SDC-401 & POS-SDC-402)
 */
@RestController
@RequestMapping("/admin/reconciliation")
public class AdminReconciliationController {

    @Autowired
    private IReconciliationService reconciliationService;
    @Autowired
    private HttpServletRequest request;

    @PostMapping("/import")
    public R importStatement(@RequestBody Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (body == null || body.get("content") == null) {
            return R.error("对账单文件内容(content)不能为空");
        }
        String channel = body.get("channel") != null ? String.valueOf(body.get("channel")) : "WECHAT";
        String fileName = body.get("file_name") != null ? String.valueOf(body.get("file_name")) : "statement.csv";
        String content = String.valueOf(body.get("content"));

        try {
            ChannelStatementBatch batch = reconciliationService.importStatement(shopId, adminId, channel, fileName, content);
            return R.ok().put("batch", batch);
        } catch (ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("对账单导入失败：" + e.getMessage());
        }
    }

    @GetMapping("/overview")
    public R getOverview(@RequestParam(required = false) String stat_date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Map<String, Object> overview = reconciliationService.getReconciliationOverview(shopId, stat_date);
            return R.ok(overview);
        } catch (ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("获取对账全景概览失败：" + e.getMessage());
        }
    }

    @GetMapping("/batches")
    public R getBatches(@RequestParam(required = false) String stat_date,
                        @RequestParam(required = false) String channel) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            List<ChannelStatementBatch> list = reconciliationService.getBatches(shopId, stat_date, channel);
            return R.ok().put("batches", list);
        } catch (Exception e) {
            return R.error("获取导入批次失败：" + e.getMessage());
        }
    }

    @GetMapping("/cases")
    public R getCases(@RequestParam(required = false) String stat_date,
                      @RequestParam(required = false) String status,
                      @RequestParam(required = false) String discrepancy_type) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            List<ReconciliationCase> list = reconciliationService.getCases(shopId, stat_date, status, discrepancy_type);
            return R.ok().put("cases", list);
        } catch (Exception e) {
            return R.error("获取差异单列表失败：" + e.getMessage());
        }
    }

    @PostMapping("/cases/{id}/resolve")
    public R resolveCase(@PathVariable("id") Long caseId,
                         @RequestBody(required = false) Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        String status = body != null && body.get("status") != null ? String.valueOf(body.get("status")) : "CLOSED";
        String resolutionNote = body != null && body.get("resolution_note") != null ? String.valueOf(body.get("resolution_note")) : null;
        String responsiblePerson = body != null && body.get("responsible_person") != null ? String.valueOf(body.get("responsible_person")) : null;

        try {
            ReconciliationCase rc = reconciliationService.resolveCase(shopId, adminId, caseId, status, resolutionNote, responsiblePerson);
            return R.ok().put("case", rc);
        } catch (ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("处理差异单失败：" + e.getMessage());
        }
    }
}
