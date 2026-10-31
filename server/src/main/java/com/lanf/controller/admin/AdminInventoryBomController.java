package com.lanf.controller.admin;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import com.lanf.inventory.service.InventoryService;
import com.lanf.inventory.web.InventoryWebSupport;
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
import java.util.Map;

/**
 * 库存扩展-BOM 版本：GET/POST/PUT /admin/inventory/boms，PUT /admin/inventory/boms/{id}/activate。
 * POST 新建版本（version_no 递增）；activate 激活：同 (shop,dish) 原 ACTIVE→HISTORY，同时仅一个有效版本；
 * 响应带版本状态（status/versionNo）。
 */
@RestController
@RequestMapping("/admin/inventory/boms")
public class AdminInventoryBomController {

    @Autowired
    private InventoryService inventoryService;
    @Autowired
    private InventoryWebSupport support;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping
    public R list(@RequestParam(defaultValue = "1") int page,
                  @RequestParam(defaultValue = "20") int pageSize,
                  @RequestParam(required = false) Integer dishId) {
        int shopId = support.requireShopId(currentRequest);
        R r = new R();
        r.put("shopId", shopId);
        r.putAll(inventoryService.listBoms(shopId, dishId, page, pageSize));
        return r;
    }

    /** 新建版本：version_no 同 (shop,dish) 递增；无 ACTIVE 时新版本直接 ACTIVE */
    @PostMapping
    public R create(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.createBomVersion(shopId, body, adminId);
        audit("bom_version_create", "bom:" + item.get("id"), item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    /** 编辑版本明细/生效时间（version_no 与 status 不经此接口变更） */
    @PutMapping
    public R update(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Long id = requireId(body);
        Map<String, Object> item = inventoryService.updateBom(shopId, id, body, adminId);
        audit("bom_update", "bom:" + id, item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    /** 激活版本：原 ACTIVE→HISTORY，仅保留此版本 ACTIVE；响应带版本状态 */
    @PutMapping("/{id}/activate")
    public R activate(@PathVariable("id") Long id) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.activateBom(shopId, id, adminId);
        audit("bom_activate", "bom:" + id, item);
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
        throw new ApiException(400, "INVENTORY_VALIDATION_FAILED", "缺少 BOM id");
    }

    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        support.audit(currentRequest, support.requireShopId(currentRequest), action, targetId,
                snapshot, support.currentAdminId(currentRequest));
    }
}
