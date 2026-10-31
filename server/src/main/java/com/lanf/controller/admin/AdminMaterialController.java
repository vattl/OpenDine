package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.*;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.*;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * 库存与成本（收银系统扩展）
 */
@RestController
@RequestMapping("/admin/material")
public class AdminMaterialController {

    @Autowired
    private IMaterialService materialService;
    @Autowired
    private IStockInService stockInService;
    @Autowired
    private IStockOutService stockOutService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/list")
    public R list(@RequestParam(required = false) String keyword) {
        Integer sid = AdminShopRequest.getResolvedShopId(request);
        QueryWrapper<Material> q = new QueryWrapper<>();
        if (sid != null) {
            q.eq("shop_id", sid);
        }
        if (keyword != null && !keyword.isEmpty()) {
            q.like("name", keyword);
        }
        q.orderByAsc("id");
        List<Material> list = materialService.list(q);
        return R.ok().put("list", list);
    }

    @PostMapping("/save")
    @AuditLog(module = "material", action = "admin_material_save", target = "#p0.id")
    public R save(@RequestBody Material material) {
        if (material == null) {
            return R.error("参数不能为空");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(request);
        if (material.getId() != null) {
            Material existing = materialService.getById(material.getId());
            R err = assertMaterialInShop(existing, sid);
            if (err != null) {
                return err;
            }
        }
        if (sid != null) {
            material.setShop_id(sid);
        }
        materialService.saveOrUpdate(material);
        return R.ok();
    }

    @PostMapping("/inbound")
    @AuditLog(module = "material", action = "admin_material_inbound")
    public R inbound(@RequestBody Map<String, Object> body) {
        Integer materialId = body != null && body.get("material_id") != null ? ((Number) body.get("material_id")).intValue() : null;
        if (materialId == null) {
            return R.error("原材料id不能为空");
        }
        BigDecimal quantity = body != null && body.get("quantity") != null ? new BigDecimal(body.get("quantity").toString()) : null;
        if (quantity == null || quantity.compareTo(BigDecimal.ZERO) <= 0) {
            return R.error("入库数量必须大于0");
        }
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        BigDecimal price = body != null && body.get("price") != null ? new BigDecimal(body.get("price").toString()) : null;
        BigDecimal totalAmount = body != null && body.get("total_amount") != null ? new BigDecimal(body.get("total_amount").toString()) : (price != null ? price.multiply(quantity) : null);
        Material m0 = materialService.getById(materialId);
        if (m0 == null) {
            return R.error("原材料不存在");
        }
        R shopErr = assertMaterialInShop(m0, AdminShopRequest.getResolvedShopId(request));
        if (shopErr != null) {
            return shopErr;
        }
        StockIn in = new StockIn();
        in.setMaterial_id(materialId);
        in.setQuantity(quantity);
        in.setPrice(price);
        in.setTotal_amount(totalAmount);
        in.setRemark((String) (body != null ? body.get("remark") : null));
        in.setOperator_id(adminId);
        in.setShop_id(AdminShopRequest.getResolvedShopId(request));
        stockInService.save(in);
        m0.setStock(m0.getStock() != null ? m0.getStock().add(quantity) : quantity);
        materialService.updateById(m0);
        return R.ok();
    }

    @PostMapping("/outbound")
    @AuditLog(module = "material", action = "admin_material_outbound")
    public R outbound(@RequestBody Map<String, Object> body) {
        Integer materialId = body != null && body.get("material_id") != null ? ((Number) body.get("material_id")).intValue() : null;
        if (materialId == null) {
            return R.error("原材料id不能为空");
        }
        BigDecimal quantity = body != null && body.get("quantity") != null ? new BigDecimal(body.get("quantity").toString()) : null;
        if (quantity == null || quantity.compareTo(BigDecimal.ZERO) <= 0) {
            return R.error("出库数量必须大于0");
        }
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        Material m0 = materialService.getById(materialId);
        if (m0 == null) {
            return R.error("原材料不存在");
        }
        R shopErr = assertMaterialInShop(m0, AdminShopRequest.getResolvedShopId(request));
        if (shopErr != null) {
            return shopErr;
        }
        StockOut out = new StockOut();
        out.setMaterial_id(materialId);
        out.setQuantity(quantity);
        out.setReason((String) (body != null ? body.get("reason") : "consume"));
        out.setRemark((String) (body != null ? body.get("remark") : null));
        out.setOperator_id(adminId);
        out.setShop_id(AdminShopRequest.getResolvedShopId(request));
        stockOutService.save(out);
        if (m0.getStock() != null) {
            m0.setStock(m0.getStock().subtract(quantity));
            materialService.updateById(m0);
        }
        return R.ok();
    }

    @GetMapping("/alert")
    public R alert() {
        Integer sid = AdminShopRequest.getResolvedShopId(request);
        QueryWrapper<Material> q = new QueryWrapper<Material>()
                .apply("alert_threshold IS NOT NULL AND stock <= alert_threshold");
        if (sid != null) {
            q.eq("shop_id", sid);
        }
        List<Material> list = materialService.list(q);
        return R.ok().put("list", list);
    }

    private R assertMaterialInShop(Material m, Integer sid) {
        if (sid == null || m == null) {
            return null;
        }
        if (m.getShop_id() != null && !m.getShop_id().equals(sid)) {
            return R.error(4003, "原料不属于当前门店");
        }
        return null;
    }
}
