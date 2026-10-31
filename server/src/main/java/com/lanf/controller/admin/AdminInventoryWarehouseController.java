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
import java.util.Map;

/**
 * 库存扩展-仓库：GET/POST/PUT /admin/inventory/warehouses。
 * legal_entity（经营主体）为调拨约束维度；写接口由拦截器按 inventory:manage 鉴权。
 */
@RestController
@RequestMapping("/admin/inventory/warehouses")
public class AdminInventoryWarehouseController {

    @Autowired
    private InventoryService inventoryService;
    @Autowired
    private InventoryWebSupport support;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping
    public R list(@RequestParam(defaultValue = "1") int page,
                  @RequestParam(defaultValue = "20") int pageSize,
                  @RequestParam(required = false) String keyword) {
        int shopId = support.requireShopId(currentRequest);
        R r = new R();
        r.put("shopId", shopId);
        r.putAll(inventoryService.listWarehouses(shopId, page, pageSize, keyword));
        return r;
    }

    @PostMapping
    public R create(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.createWarehouse(shopId, body, adminId);
        audit("warehouse_create", "warehouse:" + item.get("id"), item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    @PutMapping
    public R update(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Long id = requireId(body);
        Map<String, Object> item = inventoryService.updateWarehouse(shopId, id, body, adminId);
        audit("warehouse_update", "warehouse:" + id, item);
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
        throw new ApiException(400, "INVENTORY_VALIDATION_FAILED", "缺少仓库 id");
    }

    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        support.audit(currentRequest, support.requireShopId(currentRequest), action, targetId,
                snapshot, support.currentAdminId(currentRequest));
    }
}
