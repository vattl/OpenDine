package com.lanf.receivable.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.receivable.entity.ReceivableAccount;
import com.lanf.receivable.entity.ReceivableClaim;
import com.lanf.receivable.model.ReceivableAccountRequest;
import com.lanf.receivable.model.ReceivableActionRequest;
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
@RequestMapping("/admin/receivables")
public class AdminReceivableController {
    private static final String MERCHANT_ID = "1";

    @Autowired
    private ReceivableService receivableService;
    @Autowired
    private HttpServletRequest request;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;

    @PostMapping("/accounts")
    @AuditLog(module = "receivable", action = "admin_receivable_account_create")
    public R createAccount(@RequestBody ReceivableAccountRequest body) {
        requirePermission("receivable:manage");
        if (body == null) throw new ApiException(400, "RECEIVABLE_REQUEST_INVALID", "请求体不能为空");
        return R.ok().put("account", receivableService.createAccount(shopId(), adminId(), MERCHANT_ID,
                body.getScopeType(), body.getCustomerType(), body.getCustomerName(), body.getContactName(),
                body.getContactPhone(), body.getTaxNo(), body.getCreditLimitFen(),
                body.getPaymentTermsDays(), body.getNotes()));
    }

    @GetMapping("/accounts")
    public R accounts(@RequestParam(required = false) String status,
                      @RequestParam(required = false) String keyword,
                      @RequestParam(defaultValue = "1") long page,
                      @RequestParam(defaultValue = "20") long pageSize) {
        requirePermission("receivable:view");
        IPage<ReceivableAccount> result = receivableService.listAccounts(
                MERCHANT_ID, shopId(), status, keyword, page, pageSize);
        return R.ok().put("items", result.getRecords()).put("total", result.getTotal())
                .put("page", result.getCurrent()).put("pageSize", result.getSize());
    }

    @GetMapping("/accounts/{id}")
    public R account(@PathVariable("id") Long id) {
        requirePermission("receivable:view");
        return R.ok().put("account", receivableService.getAccount(MERCHANT_ID, shopId(), id));
    }

    @PutMapping("/accounts/{id}")
    @AuditLog(module = "receivable", action = "admin_receivable_account_update", target = "#p0")
    public R updateAccount(@PathVariable("id") Long id, @RequestBody ReceivableAccountRequest body) {
        requirePermission("receivable:manage");
        if (body == null) throw new ApiException(400, "RECEIVABLE_REQUEST_INVALID", "请求体不能为空");
        return R.ok().put("account", receivableService.updateAccount(shopId(), adminId(), MERCHANT_ID, id,
                body.getScopeType(), body.getCustomerType(), body.getCustomerName(), body.getContactName(), body.getContactPhone(),
                body.getTaxNo(), body.getCreditLimitFen(), body.getPaymentTermsDays(), body.getNotes()));
    }

    @PostMapping("/accounts/{id}/status")
    @AuditLog(module = "receivable", action = "admin_receivable_account_status", target = "#p0")
    public R accountStatus(@PathVariable("id") Long id, @RequestBody ReceivableActionRequest body) {
        requirePermission("receivable:manage");
        return R.ok().put("account", receivableService.changeAccountStatus(
                shopId(), adminId(), MERCHANT_ID, id, body != null ? body.getStatus() : null));
    }

    @PostMapping("/accounts/{id}/close")
    @AuditLog(module = "receivable", action = "admin_receivable_account_close", target = "#p0")
    public R closeAccount(@PathVariable("id") Long id) {
        requirePermission("receivable:manage");
        return R.ok().put("account", receivableService.closeAccount(shopId(), adminId(), MERCHANT_ID, id));
    }

    @DeleteMapping("/accounts/{id}")
    @AuditLog(module = "receivable", action = "admin_receivable_account_delete", target = "#p0")
    public R deleteAccount(@PathVariable("id") Long id) {
        requirePermission("receivable:manage");
        return R.ok(receivableService.deleteAccount(shopId(), adminId(), MERCHANT_ID, id));
    }

    @GetMapping("/accounts/{id}/statement")
    public R statement(@PathVariable("id") Long id,
                       @RequestParam(defaultValue = "100") int limit) {
        requirePermission("receivable:view");
        return R.ok().put("items", receivableService.statement(MERCHANT_ID, shopId(), id, limit));
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

    @GetMapping("/aging")
    public R aging() {
        requirePermission("receivable:view");
        return R.ok().put("aging", receivableService.aging(MERCHANT_ID, shopId()));
    }

    @PostMapping("/claims/{id}/collections")
    @AuditLog(module = "receivable", action = "admin_receivable_collect", target = "#p0")
    public R collect(@PathVariable("id") Long id, @RequestBody ReceivableCollectionRequest body) {
        requirePermission("receivable:collect");
        if (body == null) throw new ApiException(400, "RECEIVABLE_REQUEST_INVALID", "请求体不能为空");
        return R.ok().put("ledger", receivableService.collect(shopId(), adminId(), MERCHANT_ID, id,
                body.getAmountFen(), body.getChannel(), body.getRequestId(), body.getNote(), body.getDrawerSessionId()));
    }

    @PostMapping("/claims/{id}/reverse")
    @AuditLog(module = "receivable", action = "admin_receivable_reverse", target = "#p0")
    public R reverse(@PathVariable("id") Long id, @RequestBody ReceivableActionRequest body) {
        requirePermission("receivable:writeoff");
        return R.ok().put("ledger", receivableService.reverse(shopId(), adminId(), MERCHANT_ID, id,
                body != null ? body.getRequestId() : null, body != null ? body.getReason() : null));
    }

    @PostMapping("/claims/{id}/write-off")
    @AuditLog(module = "receivable", action = "admin_receivable_writeoff", target = "#p0")
    public R writeOff(@PathVariable("id") Long id, @RequestBody ReceivableActionRequest body) {
        requirePermission("receivable:writeoff");
        return R.ok().put("ledger", receivableService.writeOff(shopId(), adminId(), MERCHANT_ID, id,
                body != null ? body.getRequestId() : null, body != null ? body.getReason() : null));
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
