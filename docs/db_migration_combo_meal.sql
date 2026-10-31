-- 结构化套餐（M2）+ 订单明细扩展；执行后需重启应用。
-- 与 t_order_detail 行类型：normal（默认）/ combo_header / combo_component

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `t_combo` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `dish_id` int NOT NULL COMMENT '套餐头菜品 t_dish.id，唯一',
  `combo_type` varchar(16) NOT NULL DEFAULT 'groups' COMMENT 'fixed=仅固定子项; groups=含可选组',
  `status` tinyint NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_combo_dish` (`dish_id`),
  CONSTRAINT `fk_combo_dish` FOREIGN KEY (`dish_id`) REFERENCES `t_dish` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐定义头';

CREATE TABLE IF NOT EXISTS `t_combo_fixed_item` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `combo_id` bigint NOT NULL,
  `component_dish_id` int NOT NULL COMMENT '子菜 t_dish.id',
  `qty_per_combo` int NOT NULL DEFAULT 1 COMMENT '每份套餐含该子菜份数',
  `sort_order` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_combo_fixed_combo` (`combo_id`),
  CONSTRAINT `fk_combo_fixed_combo` FOREIGN KEY (`combo_id`) REFERENCES `t_combo` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_combo_fixed_component` FOREIGN KEY (`component_dish_id`) REFERENCES `t_dish` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐固定子项';

CREATE TABLE IF NOT EXISTS `t_combo_group` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `combo_id` bigint NOT NULL,
  `group_key` varchar(32) NOT NULL COMMENT '与下单 combo_selections 的 key 对应',
  `title` varchar(64) NULL DEFAULT NULL COMMENT '展示标题',
  `min_pick` int NOT NULL DEFAULT 1,
  `max_pick` int NOT NULL DEFAULT 1,
  `sort_order` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_combo_group_combo` (`combo_id`),
  CONSTRAINT `fk_combo_group_combo` FOREIGN KEY (`combo_id`) REFERENCES `t_combo` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐可选组';

CREATE TABLE IF NOT EXISTS `t_combo_group_item` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `group_id` bigint NOT NULL,
  `component_dish_id` int NOT NULL,
  `extra_price` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '相对套餐基准价的加价(元)/每份套餐',
  `sort_order` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_combo_gi_group` (`group_id`),
  CONSTRAINT `fk_combo_gi_group` FOREIGN KEY (`group_id`) REFERENCES `t_combo_group` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_combo_gi_dish` FOREIGN KEY (`component_dish_id`) REFERENCES `t_dish` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐组内可选项';

ALTER TABLE `t_order_detail`
  ADD COLUMN `line_type` varchar(20) NULL DEFAULT NULL COMMENT 'normal/combo_header/combo_component' AFTER `cid`,
  ADD COLUMN `combo_id` bigint NULL DEFAULT NULL COMMENT 't_combo.id' AFTER `line_type`,
  ADD COLUMN `combo_instance_id` varchar(40) NULL DEFAULT NULL COMMENT '同一单同一套餐实例 UUID' AFTER `combo_id`,
  ADD COLUMN `parent_detail_id` int NULL DEFAULT NULL COMMENT 'combo 子行指向头行 t_order_detail.id' AFTER `combo_instance_id`,
  ADD COLUMN `combo_selection_json` varchar(2000) NULL DEFAULT NULL COMMENT '套餐头行：用户选择(JSON)，便于复算与客服' AFTER `parent_detail_id`,
  ADD KEY `idx_order_detail_combo_inst` (`mId`, `combo_instance_id`),
  ADD KEY `idx_order_detail_line_type` (`line_type`);
