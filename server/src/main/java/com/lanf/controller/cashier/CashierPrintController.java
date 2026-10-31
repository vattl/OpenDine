package com.lanf.controller.cashier;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.UnifiedPrintRequest;
import com.lanf.printing.model.UnifiedPrintResponse;
import com.lanf.printing.service.UnifiedPrintService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 收银机-统一打印与出票调度
 */
@RestController
@RequestMapping("/cashier/print")
public class CashierPrintController {

    @Autowired
    private UnifiedPrintService unifiedPrintService;

    @Autowired
    private HttpServletRequest currentRequest;

    /**
     * 统一出票与补打入口（支持全场景）
     */
    @PostMapping("/dispatch")
    public R dispatch(@RequestBody UnifiedPrintRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(currentRequest);
        Integer adminId = currentAdminId();
        UnifiedPrintResponse resp = unifiedPrintService.dispatch(request, adminId, shopId);
        R r = R.ok(resp.getSummary());
        r.put("data", resp);
        return r;
    }

    /**
     * 兼容旧版：后厨小票补打
     */
    @PostMapping("/kitchen")
    public R kitchen(@RequestBody Map<String, Object> body) {
        String orderNo = body != null ? (String) body.get("order_no") : null;
        if (orderNo == null || orderNo.isEmpty()) {
            return R.error("订单号不能为空");
        }
        List<String> cidList = new ArrayList<>();
        Object rawCidList = body.get("cid_list");
        if (rawCidList instanceof List) {
            for (Object o : (List<?>) rawCidList) {
                if (o != null && !o.toString().trim().isEmpty()) {
                    cidList.add(o.toString().trim());
                }
            }
        }
        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo(orderNo)
                .scenario(PrintScenario.KITCHEN)
                .cidList(cidList)
                .isReprint(true)
                .build();
        Integer shopId = AdminShopRequest.getResolvedShopId(currentRequest);
        Integer adminId = currentAdminId();
        UnifiedPrintResponse resp = unifiedPrintService.dispatch(req, adminId, shopId);
        R r = R.ok(resp.getSummary());
        r.put("data", resp);
        return r;
    }

    private Integer currentAdminId() {
        if (currentRequest == null) {
            return null;
        }
        Object adminId = currentRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return adminId instanceof Integer ? (Integer) adminId : null;
    }
}
