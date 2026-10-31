package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.inventory.service.InventoryService;
import com.lanf.inventory.web.InventoryWebSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 库存扩展-采购单：GET/POST/PUT /admin/inventory/purchases。
 * POST 默认 status=PENDING_REVIEW（默认启用审核）；
 * PUT 支持 {action: approve|reject|receive}，非法跳转 400，审核动作写 audit_json + 审计。
 */
@RestController
@RequestMapping("/admin/inventory/purchases")
public class AdminInventoryPurchaseController {

    @Autowired
    private InventoryService inventoryService;
    @Autowired
    private InventoryWebSupport support;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping
    public R list(@RequestParam(defaultValue = "1") int page,
                  @RequestParam(defaultValue = "20") int pageSize,
                  @RequestParam(required = false) String status) {
        int shopId = support.requireShopId(currentRequest);
        R r = new R();
        r.put("shopId", shopId);
        r.putAll(inventoryService.listPurchases(shopId, status, page, pageSize));
        return r;
    }

    @PostMapping
    public R create(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.createPurchase(shopId, body, adminId);
        audit("purchase_create", "purchase:" + item.get("id"), snapshot(null, (String) item.get("status")));
        R r = new R();
        r.putAll(item);
        return r;
    }

    @PutMapping
    public R update(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Long id = requireId(body);
        Map<String, Object> item = inventoryService.updatePurchase(shopId, id, body, adminId);
        audit("purchase_action", "purchase:" + id,
                snapshot(String.valueOf(body.get("action")), (String) item.get("status")));
        R r = new R();
        r.putAll(item);
        return r;
    }

    private Long requireId(Map<String, Object> body) {
        Object o = body == null ? null : body.get("id");
        if (o instanceof Number) {
            return ((Number) o).longValue();
        }
        if (o instanceof String && !((String) o).trim().isEmpty()) {
            try {
                return Long.parseLong(((String) o).trim());
            } catch (NumberFormatException e) {
                // fallthrough
            }
        }
        throw new ApiException(400, "INVENTORY_VALIDATION_FAILED", "缺少采购单 id");
    }

    private Map<String, Object> snapshot(String action, String status) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("action", action);
        s.put("status", status);
        return s;
    }

    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        support.audit(currentRequest, support.requireShopId(currentRequest), action, targetId,
                snapshot, support.currentAdminId(currentRequest));
    }
}
