package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.service.KdsWorkflowV2Service;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 暴露规范化（Canonical）订单快照的查询入口（供后台管理及数据统计等 REST 客户端使用）。
 */
@RestController
@RequestMapping("/api/v1/kds")
public class KdsCanonicalQueryController {

    @Autowired
    private KdsWorkflowV2Service v2Service;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/orders/canonical")
    public R getCanonicalOrders(@RequestParam(value = "after_id", required = false) Integer afterId,
                                @RequestParam(value = "limit", defaultValue = "200") int limit) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(400, "shopId is required");
        }
        
        try {
            Map<String, Object> data = v2Service.getBusinessDayOrders(shopId, afterId, limit);
            return R.ok(data);
        } catch (Exception e) {
            return R.error(500, e.getMessage() != null ? e.getMessage() : "Failed to fetch canonical orders");
        }
    }
}
