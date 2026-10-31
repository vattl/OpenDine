package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.inventory.service.InventoryService;
import com.lanf.inventory.web.InventoryWebSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;

/**
 * 库存扩展-批次与 FEFO 建议：GET /admin/inventory/batches。
 * material_id/warehouse_id 筛选；返回批次列表 items + 每物料
 * {available 总可用量, fefoOrder 按到期日升序的批次 id 顺序}（默认 FEFO）。
 */
@RestController
@RequestMapping("/admin/inventory/batches")
public class AdminInventoryBatchController {

    @Autowired
    private InventoryService inventoryService;
    @Autowired
    private InventoryWebSupport support;
    @Autowired
    private HttpServletRequest currentRequest;

    @GetMapping
    public R list(@RequestParam(defaultValue = "1") int page,
                  @RequestParam(defaultValue = "20") int pageSize,
                  @RequestParam(required = false, name = "material_id") Integer materialId,
                  @RequestParam(required = false, name = "materialId") Integer materialIdCamel,
                  @RequestParam(required = false, name = "warehouse_id") Long warehouseId,
                  @RequestParam(required = false, name = "warehouseId") Long warehouseIdCamel) {
        int shopId = support.requireShopId(currentRequest);
        Integer material = materialId != null ? materialId : materialIdCamel;
        Long warehouse = warehouseId != null ? warehouseId : warehouseIdCamel;
        R r = new R();
        r.put("shopId", shopId);
        r.putAll(inventoryService.listBatches(shopId, material, warehouse, page, pageSize));
        return r;
    }
}
