package com.lanf.receivable.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.receivable.entity.ReceivableClaim;
import com.lanf.receivable.model.ReceivableChargeRequest;
import com.lanf.receivable.model.ReceivableCollectionRequest;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Set;

@RestController
@RequestMapping("/cashier/receivables")
public class CashierReceivableController {
    private static final String MERCHANT_ID = "1";

    @Autowired
    private ReceivableService receivableService;
    @Autowired
    private HttpServletRequest request;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;

    @GetMapping("/eligible-accounts")
    public R eligibleAccounts() {
        requirePermission("receivable:view");
        return R.ok().put("accounts", receivableService.eligibleAccounts(MERCHANT_ID, shopId()));
    }

    @PostMapping("/charges")
    @AuditLog(module = "receivable", action = "cashier_receivable_charge", target = "#p0.orderNo")
    public R charge(@RequestBody ReceivableChargeRequest body) {
        requirePermission("receivable:charge");
        if (body == null) throw new ApiException(400, "RECEIVABLE_REQUEST_INVALID", "请求体不能为空");
        ReceivableClaim claim = receivableService.charge(shopId(), adminId(), MERCHANT_ID,
                body.getOrderNo(), body.getAccountId(), body.getRequestId(), body.getNote());
        return R.ok().put("claim", claim);
    }

    @GetMapping("/claims")
    public R claims(@RequestParam(required = false) Long accountId,
                    @RequestParam(required = false) String status,
                    @RequestParam(defaultValue = "1") long page,
                    @RequestParam(defaultValue = "20") long pageSize) {
        requirePermission("receivable:view");
        IPage<ReceivableClaim> result = receivableService.listClaims(
                MERCHANT_ID, shopId(), accountId, status, page, pageSize);
        return R.ok().put("items", result.getRecords()).put("total", result.getTotal())
                .put("page", result.getCurrent()).put("pageSize", result.getSize());
    }

    @GetMapping("/claims/{id}")
    public R claim(@PathVariable("id") Long id) {
        requirePermission("receivable:view");
        return R.ok().put("claim", receivableService.getClaim(MERCHANT_ID, shopId(), id));
    }

    @PostMapping("/claims/{id}/collections")
    @AuditLog(module = "receivable", action = "cashier_receivable_collect", target = "#p0")
    public R collect(@PathVariable("id") Long id, @RequestBody ReceivableCollectionRequest body) {
        requirePermission("receivable:collect");
        if (body == null) throw new ApiException(400, "RECEIVABLE_REQUEST_INVALID", "请求体不能为空");
        return R.ok().put("ledger", receivableService.collect(shopId(), adminId(), MERCHANT_ID, id,
                body.getAmountFen(), body.getChannel(), body.getRequestId(), body.getNote(), body.getDrawerSessionId()));
    }

    private Integer shopId() { return AdminShopRequest.getResolvedShopId(request); }
    private Integer adminId() {
        Object value = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return value instanceof Integer ? (Integer) value : null;
    }

    private void requirePermission(String permission) {
        Integer operatorId = adminId();
        if (operatorId == null) {
            throw new ApiException(403, "RECEIVABLE_PERMISSION_DENIED", "无法识别当前操作人");
        }
        Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId(operatorId);
        boolean allowed = permissions != null && (permissions.contains(permission)
                || permissions.contains("admin:manage"));
        if (!allowed && !adminShopAccessService.isSuperAdmin(operatorId)) {
            throw new ApiException(403, "RECEIVABLE_PERMISSION_DENIED", "无挂账业务操作权限");
        }
    }
}
