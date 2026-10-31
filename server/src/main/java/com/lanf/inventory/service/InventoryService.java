package com.lanf.inventory.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Material;
import com.lanf.inventory.entity.InventoryBatch;
import com.lanf.inventory.entity.InventoryBom;
import com.lanf.inventory.entity.InventoryPurchase;
import com.lanf.inventory.entity.InventorySupplier;
import com.lanf.inventory.entity.InventoryTransfer;
import com.lanf.inventory.entity.InventoryWarehouse;
import com.lanf.inventory.mapper.InventoryBatchMapper;
import com.lanf.inventory.mapper.InventoryBomMapper;
import com.lanf.inventory.mapper.InventoryPurchaseMapper;
import com.lanf.inventory.mapper.InventorySupplierMapper;
import com.lanf.inventory.mapper.InventoryTransferMapper;
import com.lanf.inventory.mapper.InventoryWarehouseMapper;
import com.lanf.mapper.MaterialMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;

/**
 * 库存扩展服务：供应商 / 仓库 / BOM 版本 / 采购单(审核状态机) / 调拨(跨主体禁止 + FEFO) / 批次。
 * 契约见《系统设置后端协调文档》§2 库存七行、§4 错误码、§5 联调验收；
 * 通用规范见 docs/_settings_api_dev_spec.md（门店隔离、稳定错误码、ISO8601 时间）。
 */
@Service
public class InventoryService {

    private static final Logger log = LoggerFactory.getLogger(InventoryService.class);

    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;

    public static final String CODE_VALIDATION = "INVENTORY_VALIDATION_FAILED";

    public static final String STATUS_ENABLED = "ENABLED";
    public static final String STATUS_DISABLED = "DISABLED";

    public static final String BOM_ACTIVE = "ACTIVE";
    public static final String BOM_HISTORY = "HISTORY";

    public static final String PUR_DRAFT = "DRAFT";
    public static final String PUR_PENDING_REVIEW = "PENDING_REVIEW";
    public static final String PUR_APPROVED = "APPROVED";
    public static final String PUR_REJECTED = "REJECTED";
    public static final String PUR_RECEIVED = "RECEIVED";

    public static final String TRF_OUTBOUND = "OUTBOUND";
    public static final String TRF_IN_TRANSIT = "IN_TRANSIT";
    public static final String TRF_RECEIVED = "RECEIVED";

    @Autowired
    private InventorySupplierMapper supplierMapper;
    @Autowired
    private InventoryWarehouseMapper warehouseMapper;
    @Autowired
    private InventoryBomMapper bomMapper;
    @Autowired
    private InventoryPurchaseMapper purchaseMapper;
    @Autowired
    private InventoryTransferMapper transferMapper;
    @Autowired
    private InventoryBatchMapper batchMapper;
    @Autowired
    private MaterialMapper materialMapper;
    @Autowired
    private ObjectMapper objectMapper;

    // ==================== 供应商 ====================

    /** 供应商分页列表；settlement_info 仅 inventory:manage 可见（view 角色读取时置 null） */
    public Map<String, Object> listSuppliers(int shopId, boolean canManage, int page, int pageSize, String keyword) {
        QueryWrapper<InventorySupplier> q = new QueryWrapper<InventorySupplier>().eq("shop_id", shopId);
        if (keyword != null && !keyword.trim().isEmpty()) {
            q.like("name", keyword.trim());
        }
        q.orderByAsc("id");
        List<Map<String, Object>> items = new ArrayList<>();
        for (InventorySupplier s : supplierMapper.selectList(q)) {
            items.add(supplierMap(s, canManage));
        }
        return paged(page, pageSize, items);
    }

    public Map<String, Object> getSupplier(int shopId, Long id, boolean canManage) {
        return supplierMap(requireSupplier(shopId, id), canManage);
    }

    public Map<String, Object> createSupplier(int shopId, Map<String, Object> body, Integer adminId) {
        InventorySupplier s = new InventorySupplier();
        s.setShop_id(shopId);
        applySupplier(s, body);
        s.setCreated_at(now());
        s.setUpdated_at(now());
        supplierMapper.insert(s);
        log.info("[inventory] supplier created: shop={}, id={}, admin={}", shopId, s.getId(), adminId);
        return supplierMap(s, true);
    }

    public Map<String, Object> updateSupplier(int shopId, Long id, Map<String, Object> body, Integer adminId) {
        InventorySupplier s = requireSupplier(shopId, id);
        applySupplier(s, body);
        s.setUpdated_at(now());
        supplierMapper.updateById(s);
        log.info("[inventory] supplier updated: shop={}, id={}, admin={}", shopId, id, adminId);
        return supplierMap(s, true);
    }

    public void deleteSupplier(int shopId, Long id, Integer adminId) {
        InventorySupplier s = requireSupplier(shopId, id);
        supplierMapper.deleteById(s.getId());
        log.info("[inventory] supplier deleted: shop={}, id={}, admin={}", shopId, id, adminId);
    }

    private InventorySupplier requireSupplier(int shopId, Long id) {
        if (id == null) {
            throw new ApiException(400, CODE_VALIDATION, "缺少供应商 id");
        }
        InventorySupplier s = supplierMapper.selectById(id);
        if (s == null || !Integer.valueOf(shopId).equals(s.getShop_id())) {
            throw new ApiException(404, "INVENTORY_SUPPLIER_NOT_FOUND", "供应商不存在");
        }
        return s;
    }

    private void applySupplier(InventorySupplier s, Map<String, Object> body) {
        String name = str(body, "name");
        if (name == null || name.trim().isEmpty()) {
            throw new ApiException(400, CODE_VALIDATION, "供应商名称不能为空");
        }
        s.setName(name.trim());
        s.setContact_name(str(body, "contactName", "contact_name"));
        s.setContact_phone(str(body, "contactPhone", "contact_phone"));
        s.setSupply_scope(str(body, "supplyScope", "supply_scope"));
        s.setSettlement_info(str(body, "settlementInfo", "settlement_info"));
        String status = str(body, "status");
        if (status != null) {
            if (!STATUS_ENABLED.equals(status) && !STATUS_DISABLED.equals(status)) {
                throw new ApiException(400, CODE_VALIDATION, "status 仅允许 ENABLED/DISABLED");
            }
            s.setStatus(status);
        } else if (s.getStatus() == null) {
            s.setStatus(STATUS_ENABLED);
        }
    }

    private Map<String, Object> supplierMap(InventorySupplier s, boolean canManage) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", s.getId());
        m.put("shopId", s.getShop_id());
        m.put("name", s.getName());
        m.put("contactName", s.getContact_name());
        m.put("contactPhone", s.getContact_phone());
        m.put("supplyScope", s.getSupply_scope());
        // 结算字段按权限过滤：view 角色读取时置 null（协调文档 §2 供应商行）
        m.put("settlementInfo", canManage ? s.getSettlement_info() : null);
        m.put("status", s.getStatus());
        m.put("createdAt", iso(s.getCreated_at()));
        m.put("updatedAt", iso(s.getUpdated_at()));
        return m;
    }

    // ==================== 仓库 ====================

    public Map<String, Object> listWarehouses(int shopId, int page, int pageSize, String keyword) {
        QueryWrapper<InventoryWarehouse> q = new QueryWrapper<InventoryWarehouse>().eq("shop_id", shopId);
        if (keyword != null && !keyword.trim().isEmpty()) {
            q.like("name", keyword.trim());
        }
        q.orderByAsc("id");
        List<Map<String, Object>> items = new ArrayList<>();
        for (InventoryWarehouse w : warehouseMapper.selectList(q)) {
            items.add(warehouseMap(w));
        }
        return paged(page, pageSize, items);
    }

    public Map<String, Object> createWarehouse(int shopId, Map<String, Object> body, Integer adminId) {
        InventoryWarehouse w = new InventoryWarehouse();
        w.setShop_id(shopId);
        applyWarehouse(w, body);
        w.setCreated_at(now());
        w.setUpdated_at(now());
        warehouseMapper.insert(w);
        log.info("[inventory] warehouse created: shop={}, id={}, admin={}", shopId, w.getId(), adminId);
        return warehouseMap(w);
    }

    public Map<String, Object> updateWarehouse(int shopId, Long id, Map<String, Object> body, Integer adminId) {
        InventoryWarehouse w = requireWarehouse(shopId, id);
        applyWarehouse(w, body);
        w.setUpdated_at(now());
        warehouseMapper.updateById(w);
        log.info("[inventory] warehouse updated: shop={}, id={}, admin={}", shopId, id, adminId);
        return warehouseMap(w);
    }

    private InventoryWarehouse requireWarehouse(int shopId, Long id) {
        if (id == null) {
            throw new ApiException(400, CODE_VALIDATION, "缺少仓库 id");
        }
        InventoryWarehouse w = warehouseMapper.selectById(id);
        if (w == null || !Integer.valueOf(shopId).equals(w.getShop_id())) {
            throw new ApiException(404, "INVENTORY_WAREHOUSE_NOT_FOUND", "仓库不存在");
        }
        return w;
    }

    private void applyWarehouse(InventoryWarehouse w, Map<String, Object> body) {
        String name = str(body, "name");
        if (name == null || name.trim().isEmpty()) {
            throw new ApiException(400, CODE_VALIDATION, "仓库名称不能为空");
        }
        w.setName(name.trim());
        String legalEntity = str(body, "legalEntity", "legal_entity");
        if (legalEntity == null || legalEntity.trim().isEmpty()) {
            if (w.getLegal_entity() == null) {
                throw new ApiException(400, CODE_VALIDATION, "经营主体（legalEntity）不能为空");
            }
        } else {
            w.setLegal_entity(legalEntity.trim());
        }
        w.setAddress(str(body, "address"));
        String status = str(body, "status");
        if (status != null) {
            if (!STATUS_ENABLED.equals(status) && !STATUS_DISABLED.equals(status)) {
                throw new ApiException(400, CODE_VALIDATION, "status 仅允许 ENABLED/DISABLED");
            }
            w.setStatus(status);
        } else if (w.getStatus() == null) {
            w.setStatus(STATUS_ENABLED);
        }
    }

    private Map<String, Object> warehouseMap(InventoryWarehouse w) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", w.getId());
        m.put("shopId", w.getShop_id());
        m.put("name", w.getName());
        m.put("legalEntity", w.getLegal_entity());
        m.put("address", w.getAddress());
        m.put("status", w.getStatus());
        m.put("createdAt", iso(w.getCreated_at()));
        m.put("updatedAt", iso(w.getUpdated_at()));
        return m;
    }

    // ==================== BOM 版本 ====================

    public Map<String, Object> listBoms(int shopId, Integer dishId, int page, int pageSize) {
        QueryWrapper<InventoryBom> q = new QueryWrapper<InventoryBom>().eq("shop_id", shopId);
        if (dishId != null) {
            q.eq("dish_id", dishId);
        }
        q.orderByAsc("dish_id").orderByDesc("version_no");
        List<Map<String, Object>> items = new ArrayList<>();
        for (InventoryBom b : bomMapper.selectList(q)) {
            items.add(bomMap(b));
        }
        return paged(page, pageSize, items);
    }

    /**
     * 新建 BOM 版本：version_no 同 (shop,dish) 递增；
     * 若该 (shop,dish) 当前无 ACTIVE 版本则新版本直接 ACTIVE，否则 HISTORY（激活走 PUT {id}/activate）。
     */
    public Map<String, Object> createBomVersion(int shopId, Map<String, Object> body, Integer adminId) {
        Integer dishId = intVal(body, "dishId", "dish_id");
        if (dishId == null) {
            throw new ApiException(400, CODE_VALIDATION, "dishId 不能为空");
        }
        List<Map<String, Object>> items = requireItemList(body.get("items"), "items");
        List<Map<String, Object>> normalized = normalizeBomItems(items);

        List<InventoryBom> existing = bomMapper.selectList(new QueryWrapper<InventoryBom>()
                .eq("shop_id", shopId).eq("dish_id", dishId));
        int nextVersion = 1;
        boolean hasActive = false;
        for (InventoryBom b : existing) {
            if (b.getVersion_no() != null && b.getVersion_no() >= nextVersion) {
                nextVersion = b.getVersion_no() + 1;
            }
            if (BOM_ACTIVE.equals(b.getStatus())) {
                hasActive = true;
            }
        }

        InventoryBom bom = new InventoryBom();
        bom.setShop_id(shopId);
        bom.setDish_id(dishId);
        bom.setVersion_no(nextVersion);
        bom.setStatus(hasActive ? BOM_HISTORY : BOM_ACTIVE);
        bom.setItems_json(json(normalized));
        bom.setEffective_from(parseDateTime(str(body, "effectiveFrom", "effective_from")));
        bom.setCreated_by(adminId);
        bom.setCreated_at(now());
        bom.setUpdated_at(now());
        bomMapper.insert(bom);
        log.info("[inventory] bom version created: shop={}, dish={}, version={}, status={}, admin={}",
                shopId, dishId, nextVersion, bom.getStatus(), adminId);
        return bomMap(bom);
    }

    public Map<String, Object> updateBom(int shopId, Long id, Map<String, Object> body, Integer adminId) {
        InventoryBom bom = requireBom(shopId, id);
        if (body.containsKey("items")) {
            List<Map<String, Object>> items = requireItemList(body.get("items"), "items");
            bom.setItems_json(json(normalizeBomItems(items)));
        }
        if (body.containsKey("effectiveFrom") || body.containsKey("effective_from")) {
            bom.setEffective_from(parseDateTime(str(body, "effectiveFrom", "effective_from")));
        }
        bom.setUpdated_at(now());
        bomMapper.updateById(bom);
        log.info("[inventory] bom updated: shop={}, id={}, admin={}", shopId, id, adminId);
        return bomMap(bom);
    }

    /** 激活指定版本：同 (shop,dish) 原 ACTIVE→HISTORY，保证同时仅一个有效版本 */
    public Map<String, Object> activateBom(int shopId, Long id, Integer adminId) {
        InventoryBom bom = requireBom(shopId, id);
        List<InventoryBom> actives = bomMapper.selectList(new QueryWrapper<InventoryBom>()
                .eq("shop_id", shopId).eq("dish_id", bom.getDish_id()).eq("status", BOM_ACTIVE));
        for (InventoryBom other : actives) {
            if (other.getId() != null && other.getId().equals(bom.getId())) {
                continue;
            }
            other.setStatus(BOM_HISTORY);
            other.setUpdated_at(now());
            bomMapper.updateById(other);
        }
        if (!BOM_ACTIVE.equals(bom.getStatus())) {
            bom.setStatus(BOM_ACTIVE);
            bom.setUpdated_at(now());
            bomMapper.updateById(bom);
        }
        log.info("[inventory] bom activated: shop={}, dish={}, version={}, admin={}",
                shopId, bom.getDish_id(), bom.getVersion_no(), adminId);
        return bomMap(bom);
    }

    private InventoryBom requireBom(int shopId, Long id) {
        if (id == null) {
            throw new ApiException(400, CODE_VALIDATION, "缺少 BOM id");
        }
        InventoryBom b = bomMapper.selectById(id);
        if (b == null || !Integer.valueOf(shopId).equals(b.getShop_id())) {
            throw new ApiException(404, "INVENTORY_BOM_NOT_FOUND", "BOM 版本不存在");
        }
        return b;
    }

    /** 校验并规范化 BOM 明细：materialId 存在、qty>0、alternates 为存在的原料 id 数组 */
    private List<Map<String, Object>> normalizeBomItems(List<Map<String, Object>> items) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> item : items) {
            Integer materialId = intVal(item, "materialId", "material_id");
            if (materialId == null) {
                throw new ApiException(400, CODE_VALIDATION, "items[].materialId 不能为空");
            }
            requireMaterial(materialId);
            BigDecimal qty = decVal(item, "qty");
            if (qty == null || qty.signum() <= 0) {
                throw new ApiException(400, CODE_VALIDATION, "items[].qty 必须大于 0");
            }
            Map<String, Object> n = new LinkedHashMap<>();
            n.put("materialId", materialId);
            n.put("qty", qty);
            n.put("unit", str(item, "unit"));
            List<Integer> alternates = new ArrayList<>();
            Object rawAlt = item.get("alternates");
            if (rawAlt instanceof List) {
                for (Object o : (List<?>) rawAlt) {
                    Integer altId = toInt(o);
                    if (altId == null) {
                        throw new ApiException(400, CODE_VALIDATION, "items[].alternates 必须为原料 id 数组");
                    }
                    requireMaterial(altId);
                    alternates.add(altId);
                }
            }
            n.put("alternates", alternates);
            out.add(n);
        }
        return out;
    }

    private void requireMaterial(Integer materialId) {
        Material material = materialId == null ? null : materialMapper.selectById(materialId);
        if (material == null) {
            throw new ApiException(400, CODE_VALIDATION, "原料不存在: " + materialId);
        }
    }

    private Map<String, Object> bomMap(InventoryBom b) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", b.getId());
        m.put("shopId", b.getShop_id());
        m.put("dishId", b.getDish_id());
        m.put("versionNo", b.getVersion_no());
        m.put("status", b.getStatus());
        m.put("items", parseList(b.getItems_json()));
        m.put("effectiveFrom", iso(b.getEffective_from()));
        m.put("createdAt", iso(b.getCreated_at()));
        m.put("updatedAt", iso(b.getUpdated_at()));
        return m;
    }

    // ==================== 采购单 ====================

    public Map<String, Object> listPurchases(int shopId, String status, int page, int pageSize) {
        QueryWrapper<InventoryPurchase> q = new QueryWrapper<InventoryPurchase>().eq("shop_id", shopId);
        if (status != null && !status.trim().isEmpty()) {
            q.eq("status", status.trim());
        }
        q.orderByDesc("id");
        List<Map<String, Object>> items = new ArrayList<>();
        for (InventoryPurchase p : purchaseMapper.selectList(q)) {
            items.add(purchaseMap(p));
        }
        return paged(page, pageSize, items);
    }

    /** 新建采购单：默认启用审核，status=PENDING_REVIEW */
    public Map<String, Object> createPurchase(int shopId, Map<String, Object> body, Integer adminId) {
        Long supplierId = longVal(body, "supplierId", "supplier_id");
        Long warehouseId = longVal(body, "warehouseId", "warehouse_id");
        if (supplierId == null || warehouseId == null) {
            throw new ApiException(400, CODE_VALIDATION, "supplierId/warehouseId 不能为空");
        }
        InventorySupplier supplier = supplierMapper.selectById(supplierId);
        if (supplier == null || !Integer.valueOf(shopId).equals(supplier.getShop_id())) {
            throw new ApiException(400, "INVENTORY_SUPPLIER_NOT_FOUND", "供应商不存在或不属于当前门店");
        }
        InventoryWarehouse warehouse = warehouseMapper.selectById(warehouseId);
        if (warehouse == null || !Integer.valueOf(shopId).equals(warehouse.getShop_id())) {
            throw new ApiException(400, "INVENTORY_WAREHOUSE_NOT_FOUND", "仓库不存在或不属于当前门店");
        }
        List<Map<String, Object>> items = requireItemList(body.get("items"), "items");

        InventoryPurchase p = new InventoryPurchase();
        p.setShop_id(shopId);
        p.setSupplier_id(supplierId);
        p.setWarehouse_id(warehouseId);
        p.setStatus(PUR_PENDING_REVIEW);
        p.setItems_json(json(normalizePurchaseItems(items)));
        List<Map<String, Object>> audit = new ArrayList<>();
        audit.add(auditEntry("create", null, PUR_PENDING_REVIEW, adminId, str(body, "remark")));
        p.setAudit_json(json(audit));
        p.setCreated_by(adminId);
        p.setCreated_at(now());
        p.setUpdated_at(now());
        purchaseMapper.insert(p);
        log.info("[inventory] purchase created: shop={}, id={}, status={}, admin={}",
                shopId, p.getId(), p.getStatus(), adminId);
        return purchaseMap(p);
    }

    /**
     * 采购单动作：{action: "approve"|"reject"|"receive"}。
     * 状态机：PENDING_REVIEW -approve→ APPROVED；PENDING_REVIEW -reject→ REJECTED；APPROVED -receive→ RECEIVED。
     * 非法跳转返回 400 PURCHASE_INVALID_STATUS_TRANSITION；审核动作写 audit_json。
     */
    public Map<String, Object> updatePurchase(int shopId, Long id, Map<String, Object> body, Integer adminId) {
        InventoryPurchase p = requirePurchase(shopId, id);
        String action = str(body, "action");
        if (action == null || action.trim().isEmpty()) {
            throw new ApiException(400, "PURCHASE_ACTION_REQUIRED", "必须携带 action: approve|reject|receive");
        }
        action = action.trim();
        String fromStatus = p.getStatus();
        String toStatus;
        if ("approve".equals(action)) {
            requireTransition(fromStatus, PUR_PENDING_REVIEW, action);
            toStatus = PUR_APPROVED;
        } else if ("reject".equals(action)) {
            requireTransition(fromStatus, PUR_PENDING_REVIEW, action);
            toStatus = PUR_REJECTED;
        } else if ("receive".equals(action)) {
            requireTransition(fromStatus, PUR_APPROVED, action);
            toStatus = PUR_RECEIVED;
        } else {
            throw new ApiException(400, "PURCHASE_ACTION_INVALID", "action 仅允许 approve|reject|receive");
        }

        p.setStatus(toStatus);
        List<Map<String, Object>> audit = parseList(p.getAudit_json());
        audit.add(auditEntry(action, fromStatus, toStatus, adminId,
                str(body, "reason", "remark")));
        p.setAudit_json(json(audit));
        p.setUpdated_at(now());
        purchaseMapper.updateById(p);
        log.info("[inventory] purchase {}: shop={}, id={}, {} -> {}, admin={}",
                action, shopId, id, fromStatus, toStatus, adminId);
        return purchaseMap(p);
    }

    private void requireTransition(String current, String expected, String action) {
        if (!expected.equals(current)) {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("currentStatus", current);
            data.put("action", action);
            data.put("requiredFromStatus", expected);
            throw new ApiException(400, "PURCHASE_INVALID_STATUS_TRANSITION",
                    "当前状态 " + current + " 不允许执行 " + action, data);
        }
    }

    private InventoryPurchase requirePurchase(int shopId, Long id) {
        if (id == null) {
            throw new ApiException(400, CODE_VALIDATION, "缺少采购单 id");
        }
        InventoryPurchase p = purchaseMapper.selectById(id);
        if (p == null || !Integer.valueOf(shopId).equals(p.getShop_id())) {
            throw new ApiException(404, "INVENTORY_PURCHASE_NOT_FOUND", "采购单不存在");
        }
        return p;
    }

    private List<Map<String, Object>> normalizePurchaseItems(List<Map<String, Object>> items) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> item : items) {
            Integer materialId = intVal(item, "materialId", "material_id");
            if (materialId == null) {
                throw new ApiException(400, CODE_VALIDATION, "items[].materialId 不能为空");
            }
            requireMaterial(materialId);
            BigDecimal qty = decVal(item, "qty");
            if (qty == null || qty.signum() <= 0) {
                throw new ApiException(400, CODE_VALIDATION, "items[].qty 必须大于 0");
            }
            Map<String, Object> n = new LinkedHashMap<>();
            n.put("materialId", materialId);
            n.put("qty", qty);
            n.put("unit", str(item, "unit"));
            n.put("price", decVal(item, "price"));
            n.put("remark", str(item, "remark"));
            out.add(n);
        }
        return out;
    }

    private Map<String, Object> auditEntry(String action, String fromStatus, String toStatus,
                                           Integer adminId, String reason) {
        Map<String, Object> entry = new LinkedHashMap<>();
        entry.put("action", action);
        entry.put("fromStatus", fromStatus);
        entry.put("toStatus", toStatus);
        entry.put("adminId", adminId);
        entry.put("at", iso(now()));
        entry.put("reason", reason);
        return entry;
    }

    private Map<String, Object> purchaseMap(InventoryPurchase p) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", p.getId());
        m.put("shopId", p.getShop_id());
        m.put("supplierId", p.getSupplier_id());
        m.put("warehouseId", p.getWarehouse_id());
        m.put("status", p.getStatus());
        m.put("items", parseList(p.getItems_json()));
        m.put("audit", parseList(p.getAudit_json()));
        m.put("createdAt", iso(p.getCreated_at()));
        m.put("updatedAt", iso(p.getUpdated_at()));
        return m;
    }

    // ==================== 调拨单 ====================

    public Map<String, Object> listTransfers(int shopId, String status, int page, int pageSize) {
        QueryWrapper<InventoryTransfer> q = new QueryWrapper<InventoryTransfer>().eq("shop_id", shopId);
        if (status != null && !status.trim().isEmpty()) {
            q.eq("status", status.trim());
        }
        q.orderByDesc("id");
        List<Map<String, Object>> items = new ArrayList<>();
        for (InventoryTransfer t : transferMapper.selectList(q)) {
            items.add(transferMap(t));
        }
        return paged(page, pageSize, items);
    }

    /**
     * 创建调拨：校验源/目标仓同店且 legal_entity 一致（否则 409 TRANSFER_LEGAL_ENTITY_MISMATCH）；
     * 校验批次归属与可用量；FEFO 校验（非最早到期批次跳过需 fefoOverrideReason，否则 400
     * BATCH_FEFO_OVERRIDE_REASON_REQUIRED）；通过后源批次扣减；两仓同店创建即 IN_TRANSIT，否则 OUTBOUND。
     */
    public Map<String, Object> createTransfer(int shopId, Map<String, Object> body, Integer adminId) {
        Long fromId = longVal(body, "fromWarehouseId", "from_warehouse_id");
        Long toId = longVal(body, "toWarehouseId", "to_warehouse_id");
        if (fromId == null || toId == null) {
            throw new ApiException(400, CODE_VALIDATION, "fromWarehouseId/toWarehouseId 不能为空");
        }
        InventoryWarehouse from = warehouseMapper.selectById(fromId);
        if (from == null || !Integer.valueOf(shopId).equals(from.getShop_id())) {
            throw new ApiException(404, "INVENTORY_WAREHOUSE_NOT_FOUND", "源仓库不存在或不属于当前门店");
        }
        InventoryWarehouse to = warehouseMapper.selectById(toId);
        if (to == null || !Integer.valueOf(shopId).equals(to.getShop_id())) {
            throw new ApiException(404, "INVENTORY_WAREHOUSE_NOT_FOUND", "目标仓库不存在或不属于当前门店");
        }
        if (fromId.equals(toId)) {
            throw new ApiException(400, CODE_VALIDATION, "源仓库与目标仓库不能相同");
        }
        if (!Objects.equals(from.getLegal_entity(), to.getLegal_entity())) {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("fromWarehouseId", fromId);
            data.put("toWarehouseId", toId);
            data.put("fromLegalEntity", from.getLegal_entity());
            data.put("toLegalEntity", to.getLegal_entity());
            throw new ApiException(409, "TRANSFER_LEGAL_ENTITY_MISMATCH",
                    "调拨禁止跨经营主体", data);
        }
        List<Map<String, Object>> items = requireItemList(body.get("items"), "items");

        Map<Long, InventoryBatch> batchCache = new HashMap<>();
        Map<Long, BigDecimal> remainingByBatch = new HashMap<>();
        Map<Integer, List<InventoryBatch>> availableByMaterial = new HashMap<>();
        List<Map<String, Object>> normalized = new ArrayList<>();
        for (Map<String, Object> item : items) {
            Long batchId = longVal(item, "batchId", "batch_id");
            Integer materialId = intVal(item, "materialId", "material_id");
            BigDecimal qty = decVal(item, "qty");
            if (batchId == null || materialId == null) {
                throw new ApiException(400, CODE_VALIDATION, "items[].batchId/materialId 不能为空");
            }
            if (qty == null || qty.signum() <= 0) {
                throw new ApiException(400, CODE_VALIDATION, "items[].qty 必须大于 0");
            }
            InventoryBatch batch = batchCache.computeIfAbsent(batchId, id -> batchMapper.selectById(id));
            if (batch == null || !Integer.valueOf(shopId).equals(batch.getShop_id())) {
                throw new ApiException(404, "INVENTORY_BATCH_NOT_FOUND", "批次不存在: " + batchId);
            }
            if (!fromId.equals(batch.getWarehouse_id()) || !materialId.equals(batch.getMaterial_id())) {
                throw new ApiException(400, CODE_VALIDATION, "批次与源仓库/原料不匹配: " + batchId);
            }
            BigDecimal available = remainingByBatch.containsKey(batchId)
                    ? remainingByBatch.get(batchId)
                    : (batch.getQty() == null ? BigDecimal.ZERO : batch.getQty());
            if (available.compareTo(qty) < 0) {
                Map<String, Object> data = new LinkedHashMap<>();
                data.put("batchId", batchId);
                data.put("available", available);
                data.put("requested", qty);
                throw new ApiException(400, "BATCH_QTY_INSUFFICIENT",
                        "批次可用量不足: " + batchId, data);
            }
            // FEFO：该仓该原料剩余可用量>0 中最早到期批次；非最早且缺原因 → 400
            List<InventoryBatch> availableBatches = availableByMaterial.computeIfAbsent(materialId,
                    mid -> batchMapper.selectList(new QueryWrapper<InventoryBatch>()
                            .eq("shop_id", shopId)
                            .eq("warehouse_id", fromId)
                            .eq("material_id", mid)
                            .gt("qty", BigDecimal.ZERO)));
            InventoryBatch earliest = availableBatches.stream().min(fefoComparator()).orElse(null);
            String reason = str(item, "fefoOverrideReason", "fefo_override_reason");
            if (earliest != null && !earliest.getId().equals(batchId)
                    && (reason == null || reason.trim().isEmpty())) {
                Map<String, Object> data = new LinkedHashMap<>();
                data.put("materialId", materialId);
                data.put("selectedBatchId", batchId);
                data.put("earliestBatchId", earliest.getId());
                throw new ApiException(400, "BATCH_FEFO_OVERRIDE_REASON_REQUIRED",
                        "所选批次非最早到期批次，人工跳过 FEFO 必须填写覆盖原因", data);
            }
            Map<String, Object> n = new LinkedHashMap<>();
            n.put("batchId", batchId);
            n.put("materialId", materialId);
            n.put("qty", qty);
            n.put("fefoOverrideReason", reason);
            normalized.add(n);
            remainingByBatch.put(batchId, available.subtract(qty));
        }

        // 通过校验：源批次扣减（多条明细累计）
        for (Map<String, Object> n : normalized) {
            Long batchId = (Long) n.get("batchId");
            BigDecimal qty = (BigDecimal) n.get("qty");
            InventoryBatch batch = batchCache.get(batchId);
            batch.setQty(batch.getQty().subtract(qty));
            batch.setUpdated_at(now());
            batchMapper.updateById(batch);
        }

        InventoryTransfer t = new InventoryTransfer();
        t.setShop_id(shopId);
        t.setFrom_warehouse_id(fromId);
        t.setTo_warehouse_id(toId);
        // 两仓同店（当前门店隔离下恒成立）：直接 IN_TRANSIT；跨店扩展预留 OUTBOUND
        t.setStatus(Objects.equals(from.getShop_id(), to.getShop_id()) ? TRF_IN_TRANSIT : TRF_OUTBOUND);
        t.setItems_json(json(normalized));
        t.setCreated_by(adminId);
        t.setCreated_at(now());
        t.setUpdated_at(now());
        transferMapper.insert(t);
        log.info("[inventory] transfer created: shop={}, id={}, {} -> {}, status={}, items={}, admin={}",
                shopId, t.getId(), fromId, toId, t.getStatus(), normalized.size(), adminId);
        return transferMap(t);
    }

    /** 调拨收货：IN_TRANSIT→RECEIVED，目标仓生成新批次（batch_no/expiry_date 沿用源批次） */
    public Map<String, Object> receiveTransfer(int shopId, Long id, Integer adminId) {
        InventoryTransfer t = requireTransfer(shopId, id);
        if (!TRF_IN_TRANSIT.equals(t.getStatus())) {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("currentStatus", t.getStatus());
            throw new ApiException(400, "TRANSFER_INVALID_STATUS_TRANSITION",
                    "仅 IN_TRANSIT 状态允许收货", data);
        }
        List<Map<String, Object>> items = parseList(t.getItems_json());
        for (Map<String, Object> item : items) {
            Long batchId = longVal(item, "batchId", "batch_id");
            BigDecimal qty = decVal(item, "qty");
            InventoryBatch source = batchId == null ? null : batchMapper.selectById(batchId);
            InventoryBatch nb = new InventoryBatch();
            nb.setShop_id(shopId);
            nb.setMaterial_id(source != null ? source.getMaterial_id() : intVal(item, "materialId", "material_id"));
            nb.setWarehouse_id(t.getTo_warehouse_id());
            nb.setBatch_no(source != null && source.getBatch_no() != null
                    ? source.getBatch_no() : ("T-" + t.getId()));
            nb.setQty(qty == null ? BigDecimal.ZERO : qty);
            nb.setExpiry_date(source != null ? source.getExpiry_date() : null); // 沿用源批次到期日
            nb.setCreated_at(now());
            nb.setUpdated_at(now());
            batchMapper.insert(nb);
        }
        t.setStatus(TRF_RECEIVED);
        t.setUpdated_at(now());
        transferMapper.updateById(t);
        log.info("[inventory] transfer received: shop={}, id={}, admin={}", shopId, id, adminId);
        return transferMap(t);
    }

    private InventoryTransfer requireTransfer(int shopId, Long id) {
        if (id == null) {
            throw new ApiException(400, CODE_VALIDATION, "缺少调拨单 id");
        }
        InventoryTransfer t = transferMapper.selectById(id);
        if (t == null || !Integer.valueOf(shopId).equals(t.getShop_id())) {
            throw new ApiException(404, "INVENTORY_TRANSFER_NOT_FOUND", "调拨单不存在");
        }
        return t;
    }

    private Map<String, Object> transferMap(InventoryTransfer t) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", t.getId());
        m.put("shopId", t.getShop_id());
        m.put("fromWarehouseId", t.getFrom_warehouse_id());
        m.put("toWarehouseId", t.getTo_warehouse_id());
        m.put("status", t.getStatus());
        m.put("items", parseList(t.getItems_json()));
        m.put("createdAt", iso(t.getCreated_at()));
        m.put("updatedAt", iso(t.getUpdated_at()));
        return m;
    }

    // ==================== 批次与 FEFO 建议 ====================

    /**
     * 批次列表：material_id/warehouse_id 筛选；
     * 返回 items + materials（每物料 available 总可用量 + fefoOrder 按到期日升序的批次 id 顺序）。
     */
    public Map<String, Object> listBatches(int shopId, Integer materialId, Long warehouseId,
                                           int page, int pageSize) {
        QueryWrapper<InventoryBatch> q = new QueryWrapper<InventoryBatch>().eq("shop_id", shopId);
        if (materialId != null) {
            q.eq("material_id", materialId);
        }
        if (warehouseId != null) {
            q.eq("warehouse_id", warehouseId);
        }
        q.orderByAsc("expiry_date").orderByAsc("id");
        List<InventoryBatch> all = batchMapper.selectList(q);

        List<Map<String, Object>> items = new ArrayList<>();
        for (InventoryBatch b : all) {
            items.add(batchMap(b));
        }

        Map<Integer, List<InventoryBatch>> byMaterial = new TreeMap<>();
        for (InventoryBatch b : all) {
            if (b.getQty() != null && b.getQty().signum() > 0 && b.getMaterial_id() != null) {
                byMaterial.computeIfAbsent(b.getMaterial_id(), k -> new ArrayList<>()).add(b);
            }
        }
        List<Map<String, Object>> materials = new ArrayList<>();
        for (Map.Entry<Integer, List<InventoryBatch>> e : byMaterial.entrySet()) {
            List<InventoryBatch> list = e.getValue();
            list.sort(fefoComparator());
            BigDecimal available = BigDecimal.ZERO;
            List<Long> fefoOrder = new ArrayList<>();
            for (InventoryBatch b : list) {
                available = available.add(b.getQty());
                fefoOrder.add(b.getId());
            }
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("materialId", e.getKey());
            m.put("available", available);
            m.put("fefoOrder", fefoOrder);
            materials.add(m);
        }

        Map<String, Object> out = paged(page, pageSize, items);
        out.put("materials", materials);
        return out;
    }

    /** FEFO 比较器：到期日升序，NULL 排最后，再按 id 升序保证稳定 */
    private static Comparator<InventoryBatch> fefoComparator() {
        return Comparator
                .comparing(InventoryBatch::getExpiry_date,
                        Comparator.nullsLast(Comparator.naturalOrder()))
                .thenComparing(InventoryBatch::getId);
    }

    private Map<String, Object> batchMap(InventoryBatch b) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", b.getId());
        m.put("shopId", b.getShop_id());
        m.put("materialId", b.getMaterial_id());
        m.put("warehouseId", b.getWarehouse_id());
        m.put("batchNo", b.getBatch_no());
        m.put("qty", b.getQty());
        m.put("expiryDate", b.getExpiry_date() == null ? null : b.getExpiry_date().toString());
        m.put("createdAt", iso(b.getCreated_at()));
        m.put("updatedAt", iso(b.getUpdated_at()));
        return m;
    }

    // ==================== 通用工具 ====================

    /** 内存分页（门店级数据量可控），输出规范 §2 的 page/pageSize/total/items */
    private Map<String, Object> paged(int page, int pageSize, List<Map<String, Object>> rows) {
        int p = Math.max(page, 1);
        int ps = Math.min(Math.max(pageSize, 1), 200);
        int total = rows.size();
        int fromIdx = Math.min((p - 1) * ps, total);
        int toIdx = Math.min(fromIdx + ps, total);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("page", p);
        out.put("pageSize", ps);
        out.put("total", total);
        out.put("items", new ArrayList<>(rows.subList(fromIdx, toIdx)));
        return out;
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> requireItemList(Object raw, String field) {
        if (!(raw instanceof List) || ((List<?>) raw).isEmpty()) {
            throw new ApiException(400, CODE_VALIDATION, field + " 必须为非空数组");
        }
        List<Map<String, Object>> items = new ArrayList<>();
        for (Object o : (List<?>) raw) {
            if (!(o instanceof Map)) {
                throw new ApiException(400, CODE_VALIDATION, field + "[] 必须为对象");
            }
            items.add((Map<String, Object>) o);
        }
        return items;
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> parseList(String json) {
        if (json == null || json.trim().isEmpty()) {
            return new ArrayList<>();
        }
        try {
            List<LinkedHashMap<String, Object>> parsed = objectMapper.readValue(json,
                    new TypeReference<List<LinkedHashMap<String, Object>>>() {
                    });
            return new ArrayList<>(parsed);
        } catch (Exception e) {
            log.warn("[inventory] json 解析失败，按空数组处理: {}", e.getMessage());
            return new ArrayList<>();
        }
    }

    private String json(Object o) {
        try {
            return objectMapper.writeValueAsString(o);
        } catch (Exception e) {
            throw new ApiException(500, "INVENTORY_SERIALIZE_FAILED", "JSON 序列化失败");
        }
    }

    private static String str(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Object v = body.get(k);
            if (v != null) {
                String s = String.valueOf(v).trim();
                return s.isEmpty() ? null : s;
            }
        }
        return null;
    }

    private static Integer toInt(Object o) {
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o instanceof String && !((String) o).trim().isEmpty()) {
            try {
                return Integer.parseInt(((String) o).trim());
            } catch (NumberFormatException e) {
                return null;
            }
        }
        return null;
    }

    private static Integer intVal(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Integer v = toInt(body.get(k));
            if (v != null) {
                return v;
            }
        }
        return null;
    }

    private static Long longVal(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Object o = body.get(k);
            if (o instanceof Number) {
                return ((Number) o).longValue();
            }
            if (o instanceof String && !((String) o).trim().isEmpty()) {
                try {
                    return Long.parseLong(((String) o).trim());
                } catch (NumberFormatException e) {
                    // 尝试下一个 key
                }
            }
        }
        return null;
    }

    private static BigDecimal decVal(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Object o = body.get(k);
            if (o instanceof Number) {
                return new BigDecimal(o.toString());
            }
            if (o instanceof String && !((String) o).trim().isEmpty()) {
                try {
                    return new BigDecimal(((String) o).trim());
                } catch (NumberFormatException e) {
                    // 尝试下一个 key
                }
            }
        }
        return null;
    }

    /** 解析生效时间：支持 yyyy-MM-dd 或 yyyy-MM-ddTHH:mm:ss（ISO） */
    private static LocalDateTime parseDateTime(String s) {
        if (s == null) {
            return null;
        }
        try {
            return LocalDate.parse(s).atStartOfDay();
        } catch (Exception ignore) {
            // 继续尝试完整日期时间
        }
        try {
            return LocalDateTime.parse(s);
        } catch (Exception e) {
            throw new ApiException(400, CODE_VALIDATION, "时间格式必须为 yyyy-MM-dd 或 ISO8601 日期时间");
        }
    }

    private static LocalDateTime now() {
        return LocalDateTime.now(ZONE);
    }

    private static String iso(LocalDateTime time) {
        return time == null ? null : time.atZone(ZONE).format(ISO);
    }
}
