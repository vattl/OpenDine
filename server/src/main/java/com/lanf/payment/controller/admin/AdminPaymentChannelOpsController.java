package com.lanf.payment.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.payment.admin.PaymentChannelOpsService;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.Map;

/**
 * 支付渠道运营扩展：停用影响判定 + 测试交易。
 * 契约见《系统设置后端协调文档》§2；渠道列表/启停见既有 /admin/payment/capabilities。
 */
@RestController
@RequestMapping("/admin/payment/channels")
public class AdminPaymentChannelOpsController {

    @Autowired
    private PaymentChannelOpsService opsService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /** 停用影响判定：未完成交易数 + 受影响入口（不含商户/密钥信息） */
    @PostMapping("/{code}/impact")
    public R impact(@PathVariable("code") String code, @RequestBody Map<String, Object> body) {
        String targetStatus = body == null ? null : String.valueOf(body.get("targetStatus"));
        return R.ok(opsService.impact(requireShopId(), code, targetStatus));
    }

    /** 测试交易（幂等）：真实扣款依赖 C 端 openid 上下文，此处执行渠道就绪校验并留痕 */
    @PostMapping("/{code}/test")
    public R test(@PathVariable("code") String code, @RequestBody Map<String, Object> body) {
        if (body == null) {
            throw new ApiException(400, PaymentChannelOpsService.ERROR_VALIDATION, "请求体不能为空");
        }
        BigDecimal amount = body.get("amount") != null ? new BigDecimal(String.valueOf(body.get("amount"))) : null;
        String terminal = body.get("terminal") == null ? null : String.valueOf(body.get("terminal"));
        String idemKey = body.get("idempotencyKey") == null ? null : String.valueOf(body.get("idempotencyKey"));
        Map<String, Object> result = opsService.testTransaction(
                requireShopId(), code, amount, terminal, idemKey, currentAdminId());
        audit("payment_test_txn", String.valueOf(result.get("paymentId")));
        return R.ok(result);
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
                    "payment", action, targetId, currentAdminId(), null, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
