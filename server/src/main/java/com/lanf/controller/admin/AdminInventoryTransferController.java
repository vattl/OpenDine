package com.lanf.controller.admin;

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
 * 库存扩展-调拨单：GET/POST /admin/inventory/transfers，PUT /admin/inventory/transfers/{id}/receive。
 * POST：源/目标仓 legal_entity 一致性校验（409 TRANSFER_LEGAL_ENTITY_MISMATCH）、批次可用量与 FEFO 校验
 * （400 BATCH_FEFO_OVERRIDE_REASON_REQUIRED），通过后源批次扣减；两仓同店创建即 IN_TRANSIT。
 * receive：IN_TRANSIT→RECEIVED，目标仓生成新批次（expiry_date 沿用源批次）。
 */
@RestController
@RequestMapping("/admin/inventory/transfers")
public class AdminInventoryTransferController {

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
        r.putAll(inventoryService.listTransfers(shopId, status, page, pageSize));
        return r;
    }

    @PostMapping
    public R create(@RequestBody Map<String, Object> body) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.createTransfer(shopId, body, adminId);
        audit("transfer_create", "transfer:" + item.get("id"), item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    @PutMapping("/{id}/receive")
    public R receive(@PathVariable("id") Long id) {
        int shopId = support.requireShopId(currentRequest);
        Integer adminId = support.currentAdminId(currentRequest);
        Map<String, Object> item = inventoryService.receiveTransfer(shopId, id, adminId);
        audit("transfer_receive", "transfer:" + id, item);
        R r = new R();
        r.putAll(item);
        return r;
    }

    private void audit(String action, String targetId, Map<String, Object> snapshot) {
        support.audit(currentRequest, support.requireShopId(currentRequest), action, targetId,
                snapshot, support.currentAdminId(currentRequest));
    }
}
