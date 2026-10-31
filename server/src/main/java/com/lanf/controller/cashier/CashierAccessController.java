package com.lanf.controller.cashier;

import com.lanf.access.service.ApprovalService;
import com.lanf.access.service.AccessService;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.StringUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * 收银端权限审批授权接口 (POS Access Control v2)
 * 供收银员触发高风险/超限操作时，由店长现场输入密码或PIN码授权并签发短时一次性 Token。
 */
@RestController
@RequestMapping("/cashier/access")
public class CashierAccessController {

    @Autowired
    private ApprovalService approvalService;
    @Autowired
    private AccessService accessService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/recent-authors")
    public R recentAuthors(@RequestParam(defaultValue = "10") int limit) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文，请在请求头传递 X-Shop-Id");
        }
        List<Map<String, Object>> authors = accessService.recentAuthors(shopId, limit);
        return R.ok().put("data", authors);
    }

    @PostMapping("/authorize")
    public R authorize(@RequestBody Map<String, Object> body) {
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null && body.get("shopId") instanceof Number) {
            shopId = ((Number) body.get("shopId")).intValue();
        }
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文，请在请求头传递 X-Shop-Id 或在请求体指定 shopId");
        }

        String permission = text(body, "permission", "permission_code", "permissionCode");
        String bizType = text(body, "bizType", "biz_type");
        String bizId = text(body, "bizId", "biz_id", "orderNo", "order_no");
        BigDecimal amount = null;
        Object amtRaw = body.get("amount");
        if (amtRaw != null) {
            try {
                amount = new BigDecimal(amtRaw.toString());
            } catch (Exception ignore) {}
        }
        String reason = text(body, "reason");
        String authorizerAccount = text(body, "authorizerAccount", "authorizer_account", "managerAccount", "account");
        String credential = text(body, "credential", "password", "pin");
        String authMethod = text(body, "authMethod", "auth_method");
        if (StringUtil.isEmpty(authMethod)) {
            authMethod = "PASSWORD";
        }
        String requestId = request.getHeader("X-Client-Request-Id");
        if (StringUtil.isEmpty(requestId)) {
            requestId = text(body, "requestId", "request_id");
        }
        String terminalId = text(body, "terminalId", "terminal_id");
        if (StringUtil.isEmpty(terminalId)) {
            terminalId = request.getHeader("X-Terminal-Id");
        }
        Integer bindingVersion = integer(body, "bindingVersion", "binding_version");

        Map<String, Object> result = approvalService.authorizeAndCreateToken(
                adminId,
                shopId,
                permission,
                bizType,
                bizId,
                amount,
                reason,
                authorizerAccount,
                credential,
                authMethod,
                requestId,
                terminalId,
                bindingVersion
        );

        return R.ok(result);
    }

    @PostMapping("/qr/create")
    public R createQrApproval(@RequestBody Map<String, Object> body) {
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null && body.get("shopId") instanceof Number) {
            shopId = ((Number) body.get("shopId")).intValue();
        }
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文，请在请求头传递 X-Shop-Id 或在请求体指定 shopId");
        }

        String permission = text(body, "permission", "permission_code", "permissionCode");
        String bizType = text(body, "bizType", "biz_type");
        String bizId = text(body, "bizId", "biz_id", "orderNo", "order_no");
        BigDecimal amount = null;
        Object amtRaw = body.get("amount");
        if (amtRaw != null) {
            try {
                amount = new BigDecimal(amtRaw.toString());
            } catch (Exception ignore) {}
        }
        String reason = text(body, "reason");
        String requestId = request.getHeader("X-Client-Request-Id");
        if (StringUtil.isEmpty(requestId)) {
            requestId = text(body, "requestId", "request_id");
        }
        String terminalId = text(body, "terminalId", "terminal_id");
        if (StringUtil.isEmpty(terminalId)) {
            terminalId = request.getHeader("X-Terminal-Id");
        }
        Integer bindingVersion = integer(body, "bindingVersion", "binding_version");

        Map<String, Object> result = approvalService.createQrApproval(
                adminId,
                shopId,
                permission,
                bizType,
                bizId,
                amount,
                reason,
                requestId,
                terminalId,
                bindingVersion
        );
        return R.ok(result);
    }

    @org.springframework.web.bind.annotation.GetMapping("/qr/status")
    public R getQrApprovalStatus(@org.springframework.web.bind.annotation.RequestParam("approvalCode") String approvalCode) {
        Map<String, Object> result = approvalService.getQrApprovalStatus(approvalCode);
        return R.ok(result);
    }


    private String text(Map<String, Object> map, String... keys) {
        if (map == null) return null;
        for (String k : keys) {
            Object v = map.get(k);
            if (v != null && org.springframework.util.StringUtils.hasText(String.valueOf(v))) {
                return String.valueOf(v).trim();
            }
        }
        return null;
    }

    private Integer integer(Map<String, Object> map, String... keys) {
        String value = text(map, keys);
        if (value == null) return null;
        try {
            return Integer.valueOf(value);
        } catch (NumberFormatException ex) {
            throw new com.lanf.common.ApiException(
                    400, "ACCESS_BINDING_VERSION_INVALID", "bindingVersion 必须是整数");
        }
    }
}
