-- ============================================================
-- 库存扩展模块（协调文档 §2 库存七行 / §4 错误码 / §5 联调验收）
-- 覆盖：供应商 / 仓库 / BOM 版本 / 采购单 / 调拨单 / 批次(FEFO)
-- 幂等：可重复执行；已有数据零影响。utf8mb4，全列 COMMENT。
-- ============================================================

-- 1) 供应商
CREATE TABLE IF NOT EXISTS `t_inventory_supplier` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `shop_id` int NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `name` varchar(128) NOT NULL COMMENT '供应商名称',
  `contact_name` varchar(64) DEFAULT NULL COMMENT '联系人姓名',
  `contact_phone` varchar(32) DEFAULT NULL COMMENT '联系电话',
  `supply_scope` varchar(512) DEFAULT NULL COMMENT '供货范围（原料品类/品牌等描述）',
  `settlement_info` varchar(512) DEFAULT NULL COMMENT '结算信息（结算方式/账期/账户摘要），仅 inventory:manage 权限可见',
  `status` varchar(16) NOT NULL DEFAULT 'ENABLED' COMMENT '状态：ENABLED 启用 / DISABLED 停用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_inv_supplier_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='库存扩展-供应商';

-- 2) 仓库
CREATE TABLE IF NOT EXISTS `t_inventory_warehouse` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `shop_id` int NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `name` varchar(128) NOT NULL COMMENT '仓库名称',
  `legal_entity` varchar(128) NOT NULL COMMENT '经营主体（调拨仅允许同主体之间进行）',
  `address` varchar(256) DEFAULT NULL COMMENT '仓库地址',
  `status` varchar(16) NOT NULL DEFAULT 'ENABLED' COMMENT '状态：ENABLED 启用 / DISABLED 停用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_inv_warehouse_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='库存扩展-仓库';

-- 3) BOM 版本（同一 shop+dish 同时仅一个 ACTIVE 版本）
CREATE TABLE IF NOT EXISTS `t_inventory_bom` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `shop_id` int NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `dish_id` int NOT NULL COMMENT '菜品 t_dish.id',
  `version_no` int NOT NULL COMMENT '版本号，同 (shop_id,dish_id) 内自 1 递增',
  `status` varchar(16) NOT NULL DEFAULT 'HISTORY' COMMENT '版本状态：ACTIVE 有效（同店同菜唯一）/ HISTORY 历史',
  `items_json` longtext COMMENT 'BOM 明细 JSON [{materialId,qty,unit,alternates:[materialId…]}]',
  `effective_from` datetime DEFAULT NULL COMMENT '生效时间',
  `created_by` int DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_inv_bom_shop_dish_version` (`shop_id`,`dish_id`,`version_no`),
  KEY `idx_inv_bom_shop_dish_status` (`shop_id`,`dish_id`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='库存扩展-BOM版本';

-- 4) 采购单（默认启用审核：新建即 PENDING_REVIEW）
CREATE TABLE IF NOT EXISTS `t_inventory_purchase` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `shop_id` int NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `supplier_id` bigint NOT NULL COMMENT '供应商 t_inventory_supplier.id',
  `warehouse_id` bigint NOT NULL COMMENT '收货仓库 t_inventory_warehouse.id',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING_REVIEW' COMMENT '状态：DRAFT 草稿 / PENDING_REVIEW 待审核 / APPROVED 已审核 / REJECTED 已驳回 / RECEIVED 已收货',
  `items_json` longtext COMMENT '明细 JSON [{materialId,qty,unit,price,remark}]',
  `audit_json` longtext COMMENT '审核记录 JSON [{action,fromStatus,toStatus,adminId,at,reason}]',
  `created_by` int DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_inv_purchase_shop_status` (`shop_id`,`status`),
  KEY `idx_inv_purchase_supplier` (`supplier_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='库存扩展-采购单';

-- 5) 调拨单（禁止跨经营主体；FEFO 人工跳过需原因）
CREATE TABLE IF NOT EXISTS `t_inventory_transfer` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `shop_id` int NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `from_warehouse_id` bigint NOT NULL COMMENT '调出仓库 t_inventory_warehouse.id',
  `to_warehouse_id` bigint NOT NULL COMMENT '调入仓库 t_inventory_warehouse.id',
  `status` varchar(16) NOT NULL DEFAULT 'OUTBOUND' COMMENT '状态：OUTBOUND 已出库 / IN_TRANSIT 在途 / RECEIVED 已收货',
  `items_json` longtext COMMENT '明细 JSON [{batchId,materialId,qty,fefoOverrideReason}]，fefoOverrideReason 为人工跳过 FEFO 的原因',
  `created_by` int DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_inv_transfer_shop_status` (`shop_id`,`status`),
  KEY `idx_inv_transfer_from` (`from_warehouse_id`),
  KEY `idx_inv_transfer_to` (`to_warehouse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='库存扩展-调拨单';

-- 6) 批次（FEFO：按到期日升序消耗）
CREATE TABLE IF NOT EXISTS `t_inventory_batch` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `shop_id` int NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `material_id` int NOT NULL COMMENT '原材料 t_material.id',
  `warehouse_id` bigint NOT NULL COMMENT '所属仓库 t_inventory_warehouse.id',
  `batch_no` varchar(64) NOT NULL COMMENT '批次号（同一仓库内建议唯一，用于追溯）',
  `qty` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '剩余可用数量（>=0，出库扣减）',
  `expiry_date` date DEFAULT NULL COMMENT '到期日（FEFO 按其升序；NULL 排最后）',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_inv_batch_shop_material_wh` (`shop_id`,`material_id`,`warehouse_id`),
  KEY `idx_inv_batch_expiry` (`expiry_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='库存扩展-批次';

-- 7) 权限码注册（规范 §4 分配表：库存→inventory:view/inventory:manage）
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('inventory:view',   '库存查看', 'inventory', '库存扩展：供应商/仓库/BOM/采购/调拨/批次查看', 70),
('inventory:manage', '库存管理', 'inventory', '库存扩展：供应商/仓库/BOM/采购/调拨写操作；结算字段仅此权限可见', 71);

-- 8) 接口-权限映射（DbApiPermissionMapping 启动/重载后生效；GET 双码，写接口仅 manage）
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',    '/admin/inventory/suppliers',           'inventory:view|inventory:manage'),
('POST',   '/admin/inventory/suppliers',           'inventory:manage'),
('PUT',    '/admin/inventory/suppliers',           'inventory:manage'),
('DELETE', '/admin/inventory/suppliers',           'inventory:manage'),
('GET',    '/admin/inventory/warehouses',          'inventory:view|inventory:manage'),
('POST',   '/admin/inventory/warehouses',          'inventory:manage'),
('PUT',    '/admin/inventory/warehouses',          'inventory:manage'),
('GET',    '/admin/inventory/boms',                'inventory:view|inventory:manage'),
('POST',   '/admin/inventory/boms',                'inventory:manage'),
('PUT',    '/admin/inventory/boms',                'inventory:manage'),
('PUT',    '/admin/inventory/boms/*/activate',     'inventory:manage'),
('GET',    '/admin/inventory/purchases',           'inventory:view|inventory:manage'),
('POST',   '/admin/inventory/purchases',           'inventory:manage'),
('PUT',    '/admin/inventory/purchases',           'inventory:manage'),
('GET',    '/admin/inventory/transfers',           'inventory:view|inventory:manage'),
('POST',   '/admin/inventory/transfers',           'inventory:manage'),
('PUT',    '/admin/inventory/transfers/*/receive', 'inventory:manage'),
('GET',    '/admin/inventory/batches',             'inventory:view|inventory:manage');

-- 9) 授权：超级管理员全量；门店管理员授予查看+管理（按现有角色码）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('inventory:view','inventory:manage')
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('inventory:view','inventory:manage')
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
