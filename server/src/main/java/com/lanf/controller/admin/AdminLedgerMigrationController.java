package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.ILedgerMigrationService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 历史账本回填与双写影子切读控制器 (POS-SDC-501 & POS-SDC-502)
 */
@RestController
@RequestMapping("/admin/migration/ledger")
public class AdminLedgerMigrationController {

    @Autowired
    private ILedgerMigrationService ledgerMigrationService;
    @Autowired
    private HttpServletRequest request;

    @PostMapping("/backfill")
    public R backfill(@RequestBody(required = false) Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        String statDate = body != null && body.get("stat_date") != null ? String.valueOf(body.get("stat_date")) : null;
        boolean dryRun = body != null && Boolean.TRUE.equals(body.get("dry_run"));

        try {
            Map<String, Object> report = ledgerMigrationService.executeBackfill(shopId, adminId, statDate, dryRun);
            return R.ok(report);
        } catch (ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("历史账本回填失败：" + e.getMessage());
        }
    }

    @GetMapping("/shadow-verify")
    public R shadowVerify(@RequestParam(required = false) String stat_date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (stat_date == null || stat_date.trim().isEmpty()) {
            return R.error("必须传入待核对营业日 stat_date (yyyy-MM-dd)");
        }

        try {
            Map<String, Object> verifyRes = ledgerMigrationService.shadowVerify(shopId, stat_date.trim());
            return R.ok(verifyRes);
        } catch (ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("双写影子验证失败：" + e.getMessage());
        }
    }

    @GetMapping("/status")
    public R getStatus() {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Map<String, Object> status = ledgerMigrationService.getCutoverStatus(shopId);
            return R.ok(status);
        } catch (Exception e) {
            return R.error("获取切读与回填状态失败：" + e.getMessage());
        }
    }

    @PostMapping("/cutover")
    public R cutover(@RequestBody Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (body == null || body.get("read_source") == null) {
            return R.error("缺少必填参数 read_source (PAYMENT_LEDGER 或 LEGACY_ORDER)");
        }
        String targetSource = String.valueOf(body.get("read_source"));

        try {
            Map<String, Object> res = ledgerMigrationService.cutoverReadSource(shopId, adminId, targetSource);
            return R.ok(res);
        } catch (ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("切换读源失败：" + e.getMessage());
        }
    }
}
