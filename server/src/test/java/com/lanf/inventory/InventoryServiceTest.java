package com.lanf.inventory;

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
import com.lanf.inventory.service.InventoryService;
import com.lanf.mapper.MaterialMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 库存扩展服务单元测试（纯 Mockito，不起 Spring 容器）：
 * BOM 单激活版本、跨经营主体调拨 409、跳过 FEFO 无原因 400/带原因通过、
 * 供应商结算字段按权限过滤、采购审核状态机、调拨收货生成目标批次。
 */
class InventoryServiceTest {

    private static final int SHOP = 1;

    private InventoryService service;
    private InventorySupplierMapper supplierMapper;
    private InventoryWarehouseMapper warehouseMapper;
    private InventoryBomMapper bomMapper;
    private InventoryPurchaseMapper purchaseMapper;
    private InventoryTransferMapper transferMapper;
    private InventoryBatchMapper batchMapper;
    private MaterialMapper materialMapper;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        supplierMapper = mock(InventorySupplierMapper.class);
        warehouseMapper = mock(InventoryWarehouseMapper.class);
        bomMapper = mock(InventoryBomMapper.class);
        purchaseMapper = mock(InventoryPurchaseMapper.class);
        transferMapper = mock(InventoryTransferMapper.class);
        batchMapper = mock(InventoryBatchMapper.class);
        materialMapper = mock(MaterialMapper.class);
        objectMapper = new ObjectMapper();

        service = new InventoryService();
        ReflectionTestUtils.setField(service, "supplierMapper", supplierMapper);
        ReflectionTestUtils.setField(service, "warehouseMapper", warehouseMapper);
        ReflectionTestUtils.setField(service, "bomMapper", bomMapper);
        ReflectionTestUtils.setField(service, "purchaseMapper", purchaseMapper);
        ReflectionTestUtils.setField(service, "transferMapper", transferMapper);
        ReflectionTestUtils.setField(service, "batchMapper", batchMapper);
        ReflectionTestUtils.setField(service, "materialMapper", materialMapper);
        ReflectionTestUtils.setField(service, "objectMapper", objectMapper);
    }

    // ---------------- fixtures ----------------

    private InventoryWarehouse warehouse(long id, String legalEntity) {
        InventoryWarehouse w = new InventoryWarehouse();
        w.setId(id);
        w.setShop_id(SHOP);
        w.setName("仓" + id);
        w.setLegal_entity(legalEntity);
        w.setStatus("ENABLED");
        return w;
    }

    private InventoryBatch batch(long id, long warehouseId, int materialId, String qty, String expiry) {
        InventoryBatch b = new InventoryBatch();
        b.setId(id);
        b.setShop_id(SHOP);
        b.setMaterial_id(materialId);
        b.setWarehouse_id(warehouseId);
        b.setBatch_no("B" + id);
        b.setQty(new BigDecimal(qty));
        b.setExpiry_date(LocalDate.parse(expiry));
        return b;
    }

    private InventoryBom bom(long id, int version, String status) {
        InventoryBom b = new InventoryBom();
        b.setId(id);
        b.setShop_id(SHOP);
        b.setDish_id(100);
        b.setVersion_no(version);
        b.setStatus(status);
        return b;
    }

    private InventorySupplier supplier(String settlementInfo) {
        InventorySupplier s = new InventorySupplier();
        s.setId(9L);
        s.setShop_id(SHOP);
        s.setName("某供应商");
        s.setSupply_scope("蔬菜、肉类");
        s.setSettlement_info(settlementInfo);
        s.setStatus("ENABLED");
        return s;
    }

    private InventoryPurchase purchase(String status) {
        InventoryPurchase p = new InventoryPurchase();
        p.setId(10L);
        p.setShop_id(SHOP);
        p.setSupplier_id(3L);
        p.setWarehouse_id(4L);
        p.setStatus(status);
        p.setItems_json("[{\"materialId\":5,\"qty\":10}]");
        // 真实流程：create 时已写入一条 create 审计记录
        p.setAudit_json("[{\"action\":\"create\",\"fromStatus\":null,\"toStatus\":\"PENDING_REVIEW\",\"adminId\":7}]");
        return p;
    }

    private Material material(int id) {
        Material m = new Material();
        m.setId(id);
        m.setShop_id(SHOP);
        m.setName("原料" + id);
        return m;
    }

    private Map<String, Object> map(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            m.put((String) kv[i], kv[i + 1]);
        }
        return m;
    }

    // ---------------- BOM：同时仅一个有效版本 ----------------

    @Test
    void activateBomKeepsOnlyOneActiveVersionPerDish() throws Exception {
        InventoryBom active = bom(1L, 1, "ACTIVE");
        InventoryBom target = bom(2L, 2, "HISTORY");
        when(bomMapper.selectById(2L)).thenReturn(target);
        when(bomMapper.selectList(any())).thenReturn(Arrays.asList(active, target));

        Map<String, Object> result = service.activateBom(SHOP, 2L, 7);

        assertEquals("ACTIVE", result.get("status"));
        assertEquals(2, result.get("versionNo"));

        ArgumentCaptor<InventoryBom> captor = ArgumentCaptor.forClass(InventoryBom.class);
        verify(bomMapper, times(2)).updateById(captor.capture());
        List<InventoryBom> updated = captor.getAllValues();
        assertEquals(1L, updated.get(0).getId().longValue());
        assertEquals("HISTORY", updated.get(0).getStatus(), "原 ACTIVE 版本必须转为 HISTORY");
        assertEquals(2L, updated.get(1).getId().longValue());
        assertEquals("ACTIVE", updated.get(1).getStatus(), "目标版本激活");

        // 响应携带版本状态
        assertNotNull(result.get("versionNo"));
        assertTrue(result.get("items") instanceof List, "items 应为解析后的明细数组");
    }

    @Test
    void createBomVersionIncrementsAndActivatesWhenNoActiveExists() {
        when(bomMapper.selectList(any())).thenReturn(Collections.singletonList(bom(1L, 1, "HISTORY")));
        when(materialMapper.selectById(5)).thenReturn(material(5));

        Map<String, Object> body = map(
                "dishId", 100,
                "items", Collections.singletonList(map(
                        "materialId", 5, "qty", new BigDecimal("0.5"), "unit", "kg", "alternates", Arrays.asList(6))));
        when(materialMapper.selectById(6)).thenReturn(material(6));

        Map<String, Object> result = service.createBomVersion(SHOP, body, 7);

        assertEquals(2, result.get("versionNo"), "版本号在同 (shop,dish) 内递增");
        assertEquals("ACTIVE", result.get("status"), "无 ACTIVE 版本时新版本直接生效");

        // 已存在 ACTIVE 时新版本为 HISTORY
        when(bomMapper.selectList(any())).thenReturn(Arrays.asList(bom(1L, 1, "ACTIVE"), bom(2L, 2, "HISTORY")));
        Map<String, Object> second = service.createBomVersion(SHOP, body, 7);
        assertEquals(3, second.get("versionNo"));
        assertEquals("HISTORY", second.get("status"));
    }

    // ---------------- 调拨：跨经营主体必败 ----------------

    @Test
    void transferAcrossLegalEntityFails409() {
        when(warehouseMapper.selectById(1L)).thenReturn(warehouse(1L, "总部经营主体"));
        when(warehouseMapper.selectById(2L)).thenReturn(warehouse(2L, "分店经营主体"));

        Map<String, Object> body = map(
                "fromWarehouseId", 1L,
                "toWarehouseId", 2L,
                "items", Collections.singletonList(map("batchId", 11L, "materialId", 5, "qty", new BigDecimal(2))));

        ApiException ex = assertThrows(ApiException.class, () -> service.createTransfer(SHOP, body, 7));

        assertEquals(409, ex.getHttpStatus());
        assertEquals("TRANSFER_LEGAL_ENTITY_MISMATCH", ex.getErrorCode());
        verify(transferMapper, never()).insert(any(InventoryTransfer.class));
        verify(batchMapper, never()).updateById(any(InventoryBatch.class));
    }

    // ---------------- 调拨：FEFO 校验 ----------------

    @Test
    void transferSkippingFefoRequiresOverrideReason400_thenPassesWithReason() {
        when(warehouseMapper.selectById(1L)).thenReturn(warehouse(1L, "同一经营主体"));
        when(warehouseMapper.selectById(2L)).thenReturn(warehouse(2L, "同一经营主体"));
        InventoryBatch earliest = batch(11L, 1L, 5, "10", "2026-01-10");
        InventoryBatch selected = batch(12L, 1L, 5, "10", "2026-06-01");
        when(batchMapper.selectList(any())).thenReturn(Arrays.asList(earliest, selected));
        when(batchMapper.selectById(12L)).thenReturn(selected);

        // 选中非最早到期批次且无原因 → 400 BATCH_FEFO_OVERRIDE_REASON_REQUIRED
        Map<String, Object> noReason = map(
                "fromWarehouseId", 1L,
                "toWarehouseId", 2L,
                "items", Collections.singletonList(map("batchId", 12L, "materialId", 5, "qty", new BigDecimal(2))));
        ApiException ex = assertThrows(ApiException.class, () -> service.createTransfer(SHOP, noReason, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("BATCH_FEFO_OVERRIDE_REASON_REQUIRED", ex.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertEquals(11, ((Number) data.get("earliestBatchId")).intValue());
        verify(transferMapper, never()).insert(any(InventoryTransfer.class));

        // 带覆盖原因 → 通过，源批次扣减，同店创建即 IN_TRANSIT
        Map<String, Object> withReason = map(
                "fromWarehouseId", 1L,
                "toWarehouseId", 2L,
                "items", Collections.singletonList(map(
                        "batchId", 12L, "materialId", 5, "qty", new BigDecimal(2),
                        "fefoOverrideReason", "早批次包装破损无法领用")));
        Map<String, Object> result = service.createTransfer(SHOP, withReason, 7);

        assertEquals("IN_TRANSIT", result.get("status"));
        ArgumentCaptor<InventoryTransfer> transferCaptor = ArgumentCaptor.forClass(InventoryTransfer.class);
        verify(transferMapper).insert(transferCaptor.capture());
        assertTrue(transferCaptor.getValue().getItems_json().contains("早批次包装破损无法领用"),
                "覆盖原因应写入调拨明细留痕");

        ArgumentCaptor<InventoryBatch> batchCaptor = ArgumentCaptor.forClass(InventoryBatch.class);
        verify(batchMapper).updateById(batchCaptor.capture());
        assertEquals(12L, batchCaptor.getValue().getId().longValue());
        assertEquals(0, batchCaptor.getValue().getQty().compareTo(new BigDecimal("8")), "源批次应扣减 10-2=8");
    }

    @Test
    void transferEarliestFefoBatchNeedsNoReason() {
        when(warehouseMapper.selectById(1L)).thenReturn(warehouse(1L, "同一经营主体"));
        when(warehouseMapper.selectById(2L)).thenReturn(warehouse(2L, "同一经营主体"));
        InventoryBatch earliest = batch(11L, 1L, 5, "10", "2026-01-10");
        InventoryBatch later = batch(12L, 1L, 5, "10", "2026-06-01");
        when(batchMapper.selectList(any())).thenReturn(Arrays.asList(later, earliest));
        when(batchMapper.selectById(11L)).thenReturn(earliest);

        Map<String, Object> body = map(
                "fromWarehouseId", 1L,
                "toWarehouseId", 2L,
                "items", Collections.singletonList(map("batchId", 11L, "materialId", 5, "qty", new BigDecimal(3))));

        Map<String, Object> result = service.createTransfer(SHOP, body, 7);

        assertEquals("IN_TRANSIT", result.get("status"));
        ArgumentCaptor<InventoryBatch> captor = ArgumentCaptor.forClass(InventoryBatch.class);
        verify(batchMapper).updateById(captor.capture());
        assertEquals(0, captor.getValue().getQty().compareTo(new BigDecimal("7")));
    }

    // ---------------- 调拨收货 ----------------

    @Test
    void receiveTransferCreatesTargetBatchesInheritingExpiry() throws Exception {
        InventoryTransfer transfer = new InventoryTransfer();
        transfer.setId(7L);
        transfer.setShop_id(SHOP);
        transfer.setFrom_warehouse_id(1L);
        transfer.setTo_warehouse_id(2L);
        transfer.setStatus("IN_TRANSIT");
        transfer.setItems_json("[{\"batchId\":11,\"materialId\":5,\"qty\":2,\"fefoOverrideReason\":null}]");
        when(transferMapper.selectById(7L)).thenReturn(transfer);

        InventoryBatch source = batch(11L, 1L, 5, "8", "2026-01-10");
        when(batchMapper.selectById(11L)).thenReturn(source);

        Map<String, Object> result = service.receiveTransfer(SHOP, 7L, 7);

        assertEquals("RECEIVED", result.get("status"));
        ArgumentCaptor<InventoryBatch> captor = ArgumentCaptor.forClass(InventoryBatch.class);
        verify(batchMapper).insert(captor.capture());
        InventoryBatch created = captor.getValue();
        assertEquals(2L, created.getWarehouse_id().longValue(), "新批次入目标仓");
        assertEquals(5, created.getMaterial_id().intValue());
        assertEquals(0, created.getQty().compareTo(new BigDecimal("2")));
        assertEquals("B11", created.getBatch_no(), "批次号沿用源批次");
        assertEquals(LocalDate.parse("2026-01-10"), created.getExpiry_date(), "到期日沿用源批次");
    }

    // ---------------- 供应商：结算字段按权限过滤 ----------------

    @Test
    void supplierSettlementInfoFilteredByPermission() {
        when(supplierMapper.selectList(any()))
                .thenReturn(Collections.singletonList(supplier("月结45天，对公账户")));

        // inventory:manage 可见结算字段
        Map<String, Object> managed = service.listSuppliers(SHOP, true, 1, 20, null);
        List<Map<String, Object>> managedItems = (List<Map<String, Object>>) managed.get("items");
        assertEquals(1, managedItems.size());
        assertEquals("月结45天，对公账户", managedItems.get(0).get("settlementInfo"));

        // 仅 inventory:view 读取时 settlementInfo 置 null，其余字段正常
        Map<String, Object> viewed = service.listSuppliers(SHOP, false, 1, 20, null);
        List<Map<String, Object>> viewedItems = (List<Map<String, Object>>) viewed.get("items");
        assertNull(viewedItems.get(0).get("settlementInfo"), "view 角色不得读取结算字段");
        assertEquals("某供应商", viewedItems.get(0).get("name"));
        assertEquals("蔬菜、肉类", viewedItems.get(0).get("supplyScope"));
        assertEquals(1, viewed.get("total"));
    }

    // ---------------- 采购：审核状态机 ----------------

    @Test
    void purchaseCreateDefaultsToPendingReviewAndApproveFlowWritesAudit() throws Exception {
        when(supplierMapper.selectById(3L)).thenReturn(supplier("月结"));
        when(warehouseMapper.selectById(4L)).thenReturn(warehouse(4L, "主体"));
        when(materialMapper.selectById(5)).thenReturn(material(5));

        Map<String, Object> createBody = map(
                "supplierId", 3L,
                "warehouseId", 4L,
                "items", Collections.singletonList(map("materialId", 5, "qty", new BigDecimal(10))));
        Map<String, Object> created = service.createPurchase(SHOP, createBody, 7);

        assertEquals("PENDING_REVIEW", created.get("status"), "默认启用审核：新建即待审核");
        ArgumentCaptor<InventoryPurchase> insertCaptor = ArgumentCaptor.forClass(InventoryPurchase.class);
        verify(purchaseMapper).insert(insertCaptor.capture());
        InventoryPurchase inserted = insertCaptor.getValue();
        assertEquals("PENDING_REVIEW", inserted.getStatus());
        List<Map<String, Object>> auditAfterCreate =
                objectMapper.readValue(inserted.getAudit_json(),
                        new TypeReference<List<Map<String, Object>>>() {
                        });
        assertEquals(1, auditAfterCreate.size());

        // PENDING_REVIEW -approve→ APPROVED，audit_json 追加审核记录
        InventoryPurchase pending = purchase("PENDING_REVIEW");
        when(purchaseMapper.selectById(10L)).thenReturn(pending);
        Map<String, Object> approved = service.updatePurchase(SHOP, 10L, map("action", "approve"), 7);
        assertEquals("APPROVED", approved.get("status"));

        List<Map<String, Object>> audit = objectMapper.readValue(pending.getAudit_json(),
                new TypeReference<List<Map<String, Object>>>() {
                });
        assertEquals(2, audit.size(), "审核动作写 audit_json");
        assertEquals("approve", audit.get(1).get("action"));
        assertEquals("PENDING_REVIEW", audit.get(1).get("fromStatus"));
        assertEquals("APPROVED", audit.get(1).get("toStatus"));
        assertEquals(7, ((Number) audit.get(1).get("adminId")).intValue());
    }

    @Test
    void purchaseInvalidTransitionsRejected400() {
        // PENDING_REVIEW 不允许 receive
        when(purchaseMapper.selectById(10L)).thenReturn(purchase("PENDING_REVIEW"));
        ApiException receiveOnPending = assertThrows(ApiException.class,
                () -> service.updatePurchase(SHOP, 10L, map("action", "receive"), 7));
        assertEquals(400, receiveOnPending.getHttpStatus());
        assertEquals("PURCHASE_INVALID_STATUS_TRANSITION", receiveOnPending.getErrorCode());

        // APPROVED 不允许重复 approve
        when(purchaseMapper.selectById(10L)).thenReturn(purchase("APPROVED"));
        ApiException approveOnApproved = assertThrows(ApiException.class,
                () -> service.updatePurchase(SHOP, 10L, map("action", "approve"), 7));
        assertEquals("PURCHASE_INVALID_STATUS_TRANSITION", approveOnApproved.getErrorCode());

        // RECEIVED 不允许 reject
        when(purchaseMapper.selectById(10L)).thenReturn(purchase("RECEIVED"));
        ApiException rejectOnReceived = assertThrows(ApiException.class,
                () -> service.updatePurchase(SHOP, 10L, map("action", "reject"), 7));
        assertEquals("PURCHASE_INVALID_STATUS_TRANSITION", rejectOnReceived.getErrorCode());

        verify(purchaseMapper, never()).updateById(any(InventoryPurchase.class));
    }

    @Test
    void purchaseRejectAndReceiveLegalPaths() {
        // PENDING_REVIEW -reject→ REJECTED
        InventoryPurchase pending = purchase("PENDING_REVIEW");
        when(purchaseMapper.selectById(10L)).thenReturn(pending);
        Map<String, Object> rejected = service.updatePurchase(SHOP, 10L,
                map("action", "reject", "reason", "价格异常"), 7);
        assertEquals("REJECTED", rejected.get("status"));

        // APPROVED -receive→ RECEIVED
        InventoryPurchase approved = purchase("APPROVED");
        when(purchaseMapper.selectById(11L)).thenReturn(approved);
        Map<String, Object> received = service.updatePurchase(SHOP, 11L, map("action", "receive"), 7);
        assertEquals("RECEIVED", received.get("status"));
    }

    // ---------------- 批次列表：FEFO 建议 ----------------

    @Test
    void listBatchesReturnsAvailableAndFefoOrderPerMaterial() {
        InventoryBatch b1 = batch(11L, 1L, 5, "10", "2026-06-01");
        InventoryBatch b2 = batch(12L, 1L, 5, "4", "2026-01-10");
        InventoryBatch b3 = batch(13L, 2L, 8, "7", "2026-03-01");
        InventoryBatch empty = batch(14L, 1L, 5, "0", "2025-01-01");
        when(batchMapper.selectList(any())).thenReturn(Arrays.asList(b1, b2, b3, empty));

        Map<String, Object> result = service.listBatches(SHOP, null, null, 1, 20);

        assertEquals(4, result.get("total"));
        List<Map<String, Object>> materials = (List<Map<String, Object>>) result.get("materials");
        Map<String, Object> m5 = materials.stream()
                .filter(m -> ((Number) m.get("materialId")).intValue() == 5).findFirst().orElse(null);
        assertNotNull(m5);
        assertEquals(0, new BigDecimal("14").compareTo((BigDecimal) m5.get("available")), "可用量不含 0 批次");
        List<Long> fefoOrder = (List<Long>) m5.get("fefoOrder");
        assertEquals(Arrays.asList(12L, 11L), fefoOrder, "FEFO 按到期日升序，0 量批次不参与");
    }
}
