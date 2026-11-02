/*
  连锁模式 / 多门店 — 基于 docs/db_diancan.sql 的增量优化脚本
  MySQL 8.0+，字符集 utf8mb4

  使用说明：
  1. 在已执行 db_diancan.sql 的环境上按顺序执行本脚本（可先备份）。
  2. 若某列/索引已存在，请跳过对应语句或改为手动判断。
  3. 与现有迁移脚本关系：
     - db_migration_dish_stock.sql、t_coupon.apply_dish_ids 等保持独立，本脚本不重复添加。
*/

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------------
-- 1. 门店主数据 t_shop：补充连锁运营常用字段
-- ---------------------------------------------------------------------------
ALTER TABLE `t_shop`
  ADD COLUMN `latitude` decimal(10, 7) NULL DEFAULT NULL COMMENT '纬度' AFTER `address`,
  ADD COLUMN `longitude` decimal(10, 7) NULL DEFAULT NULL COMMENT '经度' AFTER `latitude`,
  ADD COLUMN `sort_order` int NOT NULL DEFAULT 0 COMMENT '列表排序，越小越靠前' AFTER `status`,
  ADD COLUMN `remark` varchar(255) NULL DEFAULT NULL COMMENT '备注' AFTER `sort_order`;

ALTER TABLE `t_shop`
  ADD INDEX `idx_shop_status_sort` (`status` ASC, `sort_order` ASC, `id` ASC);

-- ---------------------------------------------------------------------------
-- 2. 订单 t_order：绑定门店（连锁 P0）
-- ---------------------------------------------------------------------------
ALTER TABLE `t_order`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '门店ID，关联 t_shop.id' AFTER `merchantId`;

ALTER TABLE `t_order`
  ADD INDEX `idx_order_shop_time` (`shop_id` ASC, `order_time` ASC),
  ADD INDEX `idx_order_shop_openid` (`shop_id` ASC, `openid` ASC);

-- 外键可选：历史数据 shop_id 可能为空，使用 ON DELETE SET NULL 或仅索引不建 FK
-- ALTER TABLE `t_order` ADD CONSTRAINT `fk_order_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE SET NULL ON UPDATE RESTRICT;

-- ---------------------------------------------------------------------------
-- 3. 桌台 t_table：按门店隔离桌号（连锁 P0）
-- ---------------------------------------------------------------------------
ALTER TABLE `t_table`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '门店ID；NULL 表示未迁移的历史数据' AFTER `id`;

ALTER TABLE `t_table`
  ADD INDEX `idx_table_shop` (`shop_id` ASC),
  ADD UNIQUE INDEX `uk_table_shop_number` (`shop_id` ASC, `number` ASC);

-- 说明：MySQL 中 UNIQUE 允许多个 NULL（不同版本行为需留意）；若需强制非空，数据清洗后执行：
-- ALTER TABLE `t_table` MODIFY `shop_id` int NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. 优惠券 t_coupon：适用门店范围（NULL 或空 JSON 表示全部门店）
-- ---------------------------------------------------------------------------
ALTER TABLE `t_coupon`
  ADD COLUMN `apply_shop_ids` varchar(1000) NULL DEFAULT NULL COMMENT '适用门店ID JSON 数组，如 [1,2]；空/NULL 不限门店' AFTER `apply_dish_ids`;

-- ---------------------------------------------------------------------------
-- 5. 门店级菜品（可选，P2）：价格/库存与总部分离
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `t_dish_shop` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `dish_id` int NOT NULL COMMENT 't_dish.id',
  `unitprice` decimal(10, 2) NULL DEFAULT NULL COMMENT '门店覆盖价；NULL 则用 t_dish.unitprice',
  `stock` int NULL DEFAULT NULL COMMENT '门店可售库存；NULL 表示不启用门店库存，回退 t_dish.stock 逻辑',
  `onsale_override` tinyint NULL DEFAULT NULL COMMENT 'NULL 跟随总部；0 强制下架；1 强制上架',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop_dish` (`shop_id`, `dish_id`),
  KEY `idx_dish_shop_dish` (`dish_id`),
  CONSTRAINT `fk_dish_shop_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `fk_dish_shop_dish` FOREIGN KEY (`dish_id`) REFERENCES `t_dish` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店菜品覆盖（价/库存/上下架）';

-- ---------------------------------------------------------------------------
-- 6. 用户最近门店（可选，提升体验）
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `t_user_last_shop` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `openid` varchar(100) NOT NULL COMMENT 't_user.openid',
  `shop_id` int NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_openid` (`openid`),
  KEY `idx_shop` (`shop_id`),
  CONSTRAINT `fk_uls_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='用户上次选择门店';

-- ---------------------------------------------------------------------------
-- 7. 管理员可管门店（可选，P3 数据权限）
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `t_admin_shop` (
  `id` int NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL COMMENT 't_admin.id',
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_shop` (`admin_id`, `shop_id`),
  KEY `idx_shop` (`shop_id`),
  CONSTRAINT `fk_as_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `fk_as_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='管理员-可管理门店';

-- ---------------------------------------------------------------------------
-- 8. 订单日志 t_order_log：记录门店便于审计（可选）
-- ---------------------------------------------------------------------------
ALTER TABLE `t_order_log`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '冗余门店，便于按店筛选' AFTER `order_no`,
  ADD INDEX `idx_order_log_shop_created` (`shop_id` ASC, `created_at` ASC);

-- ---------------------------------------------------------------------------
-- 9. 原材料与库存（可选）：若需按门店仓库存
-- ---------------------------------------------------------------------------
-- ALTER TABLE `t_material` ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT 'NULL=总仓' AFTER `id`;
-- ALTER TABLE `t_material` ADD KEY `idx_material_shop` (`shop_id`);

-- ---------------------------------------------------------------------------
-- 10. 数据修复建议（手工执行，勿自动化）
-- ---------------------------------------------------------------------------
-- 单店历史数据：将现有订单、桌台统一补上默认门店 id（例如 1）：
-- UPDATE t_order SET shop_id = 1 WHERE shop_id IS NULL;
-- UPDATE t_table SET shop_id = 1 WHERE shop_id IS NULL;
