package com.lanf.controller.admin;

import com.lanf.access.service.AccessService;
import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * 员工与门店授权 / 角色管理 / 权限解释。
 * 契约见《系统设置后端协调文档》§2；角色被引用时禁止删除；敏感操作需二次确认。
 * 说明：本组接口属全局配置，不走门店上下文（/admin/access 不在门店豁免表中也无需门店）。
 */
@RestController
@RequestMapping("/admin/access")
public class AdminAccessController {

    @Autowired
    private AccessService accessService;
    @Autowired
    private com.lanf.access.service.ApprovalService approvalService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping("/employees")
    public R listEmployees(@RequestParam(required = false) String keyword,
                           @RequestParam(defaultValue = "1") int page,
                           @RequestParam(defaultValue = "20") int pageSize) {
        return R.ok(accessService.listEmployees(keyword, page, pageSize));
    }

    @SuppressWarnings("unchecked")
    @PostMapping("/employees")
    public R assignEmployee(@RequestBody Map<String, Object> body) {
        Map<String, Object> result = doAssign(body);
        audit("employee_assign", String.valueOf(result.get("adminId")));
        return R.ok(result);
    }

    @PutMapping("/employees/{adminId}")
    public R updateEmployee(@PathVariable("adminId") int adminId, @RequestBody Map<String, Object> body) {
        body.put("adminId", adminId);
        Map<String, Object> result = doAssign(body);
        audit("employee_update", String.valueOf(adminId));
        return R.ok(result);
    }

    @DeleteMapping("/employees/{adminId}")
    public R deleteEmployee(@PathVariable("adminId") int adminId,
                            @RequestParam(defaultValue = "false") boolean confirm) {
        accessService.deleteEmployee(adminId, confirm, currentAdminId());
        audit("employee_delete", String.valueOf(adminId));
        return R.ok("员工已删除");
    }

    private Map<String, Object> doAssign(Map<String, Object> body) {
        Object adminIdRaw = body.get("adminId");
        if (!(adminIdRaw instanceof Number)) {
            throw new ApiException(400, AccessService.ERROR_VALIDATION, "adminId 必填");
        }
        List<Integer> roleIds = toIntList(body.get("roleIds"));
        List<Integer> shopIds = toIntList(body.get("shopIds"));
        boolean confirm = Boolean.TRUE.equals(body.get("confirm")) || "true".equals(String.valueOf(body.get("confirm")));
        return accessService.assignEmployee(((Number) adminIdRaw).intValue(), roleIds, shopIds, confirm, currentAdminId());
    }

    @GetMapping("/roles")
    public R listRoles() {
        R r = new R();
        r.put("items", accessService.listRoles());
        return r;
    }

    @PostMapping("/roles")
    public R createRole(@RequestBody Map<String, Object> body) {
        Map<String, Object> result = accessService.createRole(body, currentAdminId());
        audit("role_create", String.valueOf(result.get("id")));
        return R.ok(result);
    }

    @PutMapping("/roles/{id}")
    public R updateRole(@PathVariable("id") int id, @RequestBody Map<String, Object> body) {
        Map<String, Object> result = accessService.updateRole(id, body, currentAdminId());
        audit("role_update", String.valueOf(id));
        return R.ok(result);
    }

    @DeleteMapping("/roles/{id}")
    public R deleteRole(@PathVariable("id") int id,
                        @RequestParam(defaultValue = "false") boolean confirm) {
        accessService.deleteRole(id, confirm, currentAdminId());
        audit("role_delete", String.valueOf(id));
        return R.ok("角色已删除");
    }

    @PutMapping("/employees/{adminId}/status")
    public R updateEmployeeStatus(@PathVariable("adminId") int adminId, @RequestBody Map<String, Object> body) {
        String status = body.get("status") != null ? String.valueOf(body.get("status")) : null;
        Map<String, Object> result = accessService.updateEmployeeStatus(adminId, status, currentAdminId());
        audit("employee_status_update", String.valueOf(adminId));
        return R.ok(result);
    }

    @PostMapping("/employees/{adminId}/force-logout")
    public R forceLogout(@PathVariable("adminId") int adminId) {
        accessService.forceLogout(adminId, currentAdminId());
        audit("employee_force_logout", String.valueOf(adminId));
        return R.ok("已成功强制下线");
    }

    @GetMapping("/employees/{adminId}/effective-permissions")
    public R getEffectivePermissions(@PathVariable("adminId") int adminId,
                                     @RequestParam(required = false) Integer shopId) {
        return R.ok(accessService.getEffectivePermissions(adminId, shopId));
    }

    @Autowired
    private com.lanf.access.service.AccessConflictService conflictService;

    @SuppressWarnings("unchecked")
    @PostMapping("/conflicts/check")
    public R checkConflicts(@RequestBody Map<String, Object> body) {
        Object raw = body.get("permissionCodes");
        List<String> codes = new ArrayList<>();
        if (raw instanceof List) {
            for (Object o : (List<?>) raw) {
                if (o != null) codes.add(String.valueOf(o).trim());
            }
        }
        return R.ok(Collections.singletonMap("conflicts", conflictService != null ? conflictService.findConflicts(codes) : Collections.emptyList()));
    }

    @SuppressWarnings("unchecked")
    @PostMapping("/evaluate")
    public R evaluate(@RequestBody Map<String, Object> body) {
        Object userId = body.get("userId");
        if (!(userId instanceof Number)) {
            throw new ApiException(400, AccessService.ERROR_VALIDATION, "userId 必填");
        }
        Integer shopId = body.get("shopId") instanceof Number ? ((Number) body.get("shopId")).intValue() : null;
        String permission = body.get("permission") == null ? null : String.valueOf(body.get("permission"));
        Map<String, Object> context = body.get("context") instanceof Map ? (Map<String, Object>) body.get("context") : null;
        return R.ok(accessService.evaluate(((Number) userId).intValue(), shopId, permission, context));
    }

    // ---------------- 权限策略 ----------------

    @GetMapping("/policies")
    public R listPolicies(@RequestParam(required = false) String permissionCode) {
        return R.ok(Collections.singletonMap("items", accessService.listPolicies(permissionCode)));
    }

    @PostMapping("/policies")
    public R createPolicy(@RequestBody com.lanf.entity.AccessPolicy policy) {
        com.lanf.entity.AccessPolicy created = accessService.createPolicy(policy, currentAdminId());
        audit("policy_create", String.valueOf(created.getId()));
        return R.ok().put("data", created);
    }

    @PutMapping("/policies/{id}")
    public R updatePolicy(@PathVariable("id") Long id, @RequestBody com.lanf.entity.AccessPolicy policy) {
        com.lanf.entity.AccessPolicy updated = accessService.updatePolicy(id, policy, currentAdminId());
        audit("policy_update", String.valueOf(id));
        return R.ok().put("data", updated);
    }

    @DeleteMapping("/policies/{id}")
    public R deletePolicy(@PathVariable("id") Long id) {
        accessService.deletePolicy(id, currentAdminId());
        audit("policy_delete", String.valueOf(id));
        return R.ok("策略已删除");
    }

    @PostMapping("/policies/assign")
    public R assignPolicy(@RequestBody Map<String, Object> body) {
        Integer roleId = body.get("roleId") instanceof Number ? ((Number) body.get("roleId")).intValue() : null;
        Long policyId = body.get("policyId") instanceof Number ? ((Number) body.get("policyId")).longValue() : null;
        Integer shopId = body.get("shopId") instanceof Number ? ((Number) body.get("shopId")).intValue() : null;
        if (roleId == null || policyId == null) {
            throw new ApiException(400, AccessService.ERROR_VALIDATION, "roleId 与 policyId 必填");
        }
        accessService.assignPolicyToRole(roleId, policyId, shopId, currentAdminId());
        audit("policy_assign", "role:" + roleId + "-policy:" + policyId);
        return R.ok("策略绑定成功");
    }

    // ---------------- 审批记录 ----------------

    @GetMapping("/approvals")
    public R listApprovals(@RequestParam(required = false) Integer shopId,
                           @RequestParam(required = false) String bizType,
                           @RequestParam(required = false) String status,
                           @RequestParam(defaultValue = "1") int page,
                           @RequestParam(defaultValue = "20") int pageSize) {
        return R.ok(accessService.listApprovals(shopId, bizType, status, page, pageSize));
    }

    @GetMapping("/approvals/{id}")
    public R getApproval(@PathVariable("id") Long id) {
        return R.ok().put("data", accessService.getApproval(id));
    }

    // ---------------- 扫码授权 (店长端) ----------------

    @GetMapping("/qr/details")
    public R getQrApprovalDetails(@RequestParam("approvalCode") String approvalCode) {
        return R.ok().put("data", approvalService.getQrApprovalDetails(approvalCode, currentAdminId()));
    }

    @PostMapping("/qr/confirm")
    public R confirmQrApproval(@RequestBody Map<String, Object> body) {
        String approvalCode = body.get("approvalCode") != null ? String.valueOf(body.get("approvalCode")).trim() : null;
        String action = body.get("action") != null ? String.valueOf(body.get("action")).trim() : null;
        String reason = body.get("reason") != null ? String.valueOf(body.get("reason")).trim() : null;
        Map<String, Object> result = approvalService.confirmQrApproval(approvalCode, currentAdminId(), action, reason);
        audit("qr_approval_confirm", approvalCode + ":" + action);
        return R.ok(result);
    }


    @SuppressWarnings("unchecked")
    private List<Integer> toIntList(Object raw) {
        if (!(raw instanceof List)) {
            return null;
        }
        List<Integer> out = new java.util.ArrayList<>();
        for (Object o : (List<Object>) raw) {
            if (o instanceof Number) {
                out.add(((Number) o).intValue());
            }
        }
        return out;
    }

    private Integer currentAdminId() {
        Object adminId = currentRequest.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        return adminId instanceof Integer ? (Integer) adminId : null;
    }

    private void audit(String action, String targetId) {
        try {
            securityAuditService.recordPrivilegedAction(currentRequest, null,
                    "access", action, targetId, currentAdminId(), null, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
