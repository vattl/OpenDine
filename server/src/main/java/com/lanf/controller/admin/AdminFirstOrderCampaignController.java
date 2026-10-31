package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.marketing.service.FirstOrderCampaignService;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.Map;

/**
 * 首单活动：列表 / 保存 / 资格判定 / 核销记录。
 * 契约见《系统设置后端协调文档》§2；鉴权与门店上下文由 SysInterceptor 统一处理。
 */
@RestController
@RequestMapping("/admin/marketing/first-order")
public class AdminFirstOrderCampaignController {

    @Autowired
    private FirstOrderCampaignService campaignService;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping("/campaigns")
    public R listCampaigns(@RequestParam(required = false) String status,
                           @RequestParam(defaultValue = "1") int page,
                           @RequestParam(defaultValue = "20") int pageSize) {
        return R.ok(campaignService.listCampaigns(requireShopId(), status, page, pageSize));
    }

    @PostMapping("/campaigns")
    public R createCampaign(@RequestBody Map<String, Object> body) {
        Map<String, Object> result = campaignService.createCampaign(requireShopId(), body, currentAdminId());
        audit("campaign_create", String.valueOf(result.get("id")));
        return R.ok(result);
    }

    @PutMapping("/campaigns/{id}")
    public R updateCampaign(@PathVariable("id") long id, @RequestBody Map<String, Object> body) {
        Map<String, Object> result = campaignService.updateCampaign(requireShopId(), id, body, currentAdminId());
        audit("campaign_update", String.valueOf(id));
        return R.ok(result);
    }

    @PostMapping("/eligibility/evaluate")
    public R evaluate(@RequestBody Map<String, Object> body) {
        int shopId = body.get("shopId") instanceof Number
                ? ((Number) body.get("shopId")).intValue() : requireShopId();
        String customerId = body.get("customerId") == null ? null : String.valueOf(body.get("customerId"));
        BigDecimal orderAmount = body.get("orderAmount") != null
                ? new BigDecimal(String.valueOf(body.get("orderAmount"))) : null;
        return R.ok(campaignService.evaluate(shopId, customerId, orderAmount));
    }

    @GetMapping("/redemptions")
    public R listRedemptions(@RequestParam(required = false) Long campaignId,
                             @RequestParam(required = false) String customerId,
                             @RequestParam(required = false) String orderNo,
                             @RequestParam(defaultValue = "1") int page,
                             @RequestParam(defaultValue = "20") int pageSize) {
        return R.ok(campaignService.listRedemptions(requireShopId(), campaignId, customerId, orderNo, page, pageSize));
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
                    "marketing", action, targetId, currentAdminId(), null, null);
        } catch (Exception ignore) {
            // 审计失败不影响主流程
        }
    }
}
