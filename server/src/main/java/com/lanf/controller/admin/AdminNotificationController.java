package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.notify.service.NotificationService;
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
import java.util.Map;

/**
 * 通知规则 / 试发 / 发送记录。契约见《系统设置后端协调文档》§2；
 * 鉴权与门店上下文由 SysInterceptor 统一处理。
 */
@RestController
@RequestMapping("/admin/notifications")
public class AdminNotificationController {

    @Autowired
    private NotificationService notificationService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping("/rules")
    public R listRules(@RequestParam(required = false) String eventType,
                       @RequestParam(defaultValue = "1") int page,
                       @RequestParam(defaultValue = "20") int pageSize) {
        return R.ok(notificationService.listRules(requireShopId(), eventType, page, pageSize));
    }

    @PostMapping("/rules")
    public R createRule(@RequestBody Map<String, Object> body) {
        Map<String, Object> rule = notificationService.createRule(requireShopId(), body, currentAdminId());
        audit("rule_create", String.valueOf(rule.get("id")));
        return R.ok(rule);
    }

    @PutMapping("/rules/{id}")
    public R updateRule(@PathVariable("id") long id, @RequestBody Map<String, Object> body) {
        Map<String, Object> rule = notificationService.updateRule(requireShopId(), id, body, currentAdminId());
        audit("rule_update", String.valueOf(id));
        return R.ok(rule);
    }

    @DeleteMapping("/rules/{id}")
    public R deleteRule(@PathVariable("id") long id,
                        @RequestParam(required = false) Integer version,
                        @RequestParam(defaultValue = "false") boolean confirm) {
        int shopId = requireShopId();
        notificationService.deleteRule(shopId, id, version, confirm, currentAdminId());
        audit("rule_delete", String.valueOf(id));
        return R.ok("规则已删除");
    }

    @PostMapping("/rules/{id}/test")
    public R testDelivery(@PathVariable("id") long id, @RequestBody(required = false) Map<String, Object> body) {
        Map<String, Object> result = notificationService.testDelivery(requireShopId(), id, body, currentAdminId());
        audit("rule_test_delivery", String.valueOf(id));
        return R.ok(result);
    }

    @GetMapping("/deliveries")
    public R listDeliveries(@RequestParam(required = false) Long ruleId,
                            @RequestParam(required = false) String channel,
                            @RequestParam(required = false) String status,
                            @RequestParam(required = false) String from,
                            @RequestParam(required = false) String to,
                            @RequestParam(defaultValue = "1") int page,
                            @RequestParam(defaultValue = "20") int pageSize) {
        return R.ok(notificationService.listDeliveries(requireShopId(), ruleId, channel, status, from, to, page, pageSize));
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

    private void audit(String action, String targetId) {
        try {
            securityAuditService.recordPrivilegedAction(currentRequest, requireShopId(),
                    "notifications", action, targetId, currentAdminId(), null, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
