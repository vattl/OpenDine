-- 智能预测备货系统升级：BOM + 备货计划 + 门店规则（见 docs/点餐系统（db_diancan）智能预测备货系统 落地方案（数据库升级版）.md）
-- 不修改原有业务表；与已有 t_stock_prep_forecast_run 外键关联。
-- MySQL 8：若表已存在可安全重复执行（IF NOT EXISTS）。

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `t_dish_material_bom` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '配比ID',
  `shop_id` int NOT NULL COMMENT '门店ID(t_shop.id)',
  `dish_id` int NOT NULL COMMENT '菜品ID(t_dish.id)',
  `material_id` int NOT NULL COMMENT '原材料ID(t_material.id)',
  `dosage` decimal(10,3) NOT NULL DEFAULT 0.000 COMMENT '单份菜品消耗原材料数量',
  `unit` varchar(16) NOT NULL DEFAULT '斤' COMMENT '单位：斤/克/袋/瓶',
  `loss_rate` decimal(5,2) NOT NULL DEFAULT 0.05 COMMENT '损耗率小数，如0.05=5%；消耗=销量×用量×(1+loss_rate)',
  `is_enabled` tinyint NOT NULL DEFAULT 1 COMMENT '1启用 0禁用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_dish_material` (`shop_id` ASC, `dish_id` ASC, `material_id` ASC) USING BTREE,
  KEY `idx_dish` (`dish_id` ASC) USING BTREE,
  KEY `idx_material` (`material_id` ASC) USING BTREE,
  KEY `idx_shop` (`shop_id` ASC) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='菜品-原材料配比表(BOM)';

CREATE TABLE IF NOT EXISTS `t_stock_prepare_plan` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '备货计划ID',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `run_id` bigint NOT NULL COMMENT '预测批次ID(t_stock_prep_forecast_run.id)',
  `prepare_date` date NOT NULL COMMENT '备货日期(与预测 stat_date 对齐)',
  `material_id` int NOT NULL COMMENT '原材料ID',
  `current_stock` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '生成时 t_material.stock 快照',
  `forecast_consume` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '预测消耗总量',
  `safe_stock` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '安全库存',
  `suggest_qty` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '系统建议备货量',
  `manual_adjust` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '人工调整量(±)',
  `final_qty` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '最终确认备货量',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '0待确认 1已确认 2已采购 3已入库',
  `operator_id` int NULL DEFAULT NULL COMMENT '操作员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_run_material_prepare_date` (`run_id` ASC, `material_id` ASC, `prepare_date` ASC) USING BTREE,
  KEY `idx_shop_material_date` (`shop_id` ASC, `material_id` ASC, `prepare_date` ASC) USING BTREE,
  KEY `idx_prepare_date` (`prepare_date` ASC) USING BTREE,
  KEY `idx_status` (`status` ASC) USING BTREE,
  CONSTRAINT `fk_prepare_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='原材料备货计划表';

CREATE TABLE IF NOT EXISTS `t_stock_prep_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT '门店ID',
  `safe_stock_rate` decimal(5,2) NOT NULL DEFAULT 0.10 COMMENT '安全库存系数',
  `default_loss_rate` decimal(5,2) NOT NULL DEFAULT 0.05 COMMENT 'BOM未填损耗时的默认损耗率',
  `forecast_days` int NOT NULL DEFAULT 3 COMMENT '默认预测天数',
  `history_days` int NOT NULL DEFAULT 30 COMMENT '默认回溯天数',
  `weather_factor` decimal(5,2) NOT NULL DEFAULT 1.00 COMMENT '天气修正上限参考/扩展用',
  `holiday_factor` decimal(5,2) NOT NULL DEFAULT 1.20 COMMENT '节假日参考系数/扩展用',
  `member_factor` decimal(5,2) NOT NULL DEFAULT 1.00 COMMENT '会员客流热度系数(充值不计销量，仅乘在预测上)',
  `is_enabled` tinyint NOT NULL DEFAULT 1,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop` (`shop_id` ASC) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货规则配置表(按店)';
