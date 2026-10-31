package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.inventory.service.InventoryService;
import com.lanf.inventory.web.InventoryWebSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
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
 * 库存扩展-供应商：GET/POST/PUT/DELETE /admin/inventory/suppliers。
 * settlement_info 仅 inventory:manage 可见（view 角色读取时置 null，协调文档 §2）。
 */
@RestController
@RequestMapping("/admin/inventory/suppliers")
public class AdminInventorySupplierController {

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
        boolean canManage = support.canManage(support.currentAdminId(currentRequest));
        R r = new R();
        r.put("shopId", shopId);
        r.putAll(inventoryService.listSuppliers(shopId, canManage, page, pageSize, keyword));
        return r;
    }

    @PostMapping
    public R create(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.createSupplier(shopId, body, adminId);
        audit("supplier_create", target(item), item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    @PutMapping
    public R update(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Long id = requireId(body);
        Map<String, Object> item = inventoryService.updateSupplier(shopId, id, body, adminId);
        audit("supplier_update", target(item), item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    @DeleteMapping
    public R delete(@RequestParam("id") Long id) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        inventoryService.deleteSupplier(shopId, id, adminId);
        audit("supplier_delete", "supplier:" + id, null);
        R r = new R();
        r.put("id", id);
        r.put("deleted", true);
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
        throw new ApiException(400, "INVENTORY_VALIDATION_FAILED", "缺少供应商 id");
    }

    private String target(Map<String, Object> item) {
        return "supplier:" + item.get("id");
    }

    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        support.audit(currentRequest, support.requireShopId(currentRequest), action, targetId,
                snapshot, support.currentAdminId(currentRequest));
    }
}
