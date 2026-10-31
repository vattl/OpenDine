-- 备货预测落库：一次运行 + 按日汇总 + 按日按菜明细
-- 执行前请确认库名；与现有 t_shop、t_dish 无强外键（仅语义关联 shop_id、dish_id）。

CREATE TABLE IF NOT EXISTS `t_stock_prep_forecast_run` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NULL DEFAULT NULL COMMENT '门店ID，与订单统计一致；NULL 表示未按店过滤的汇总',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '生成时间',
  `history_days` int NOT NULL COMMENT '回溯天数',
  `forecast_days` int NOT NULL COMMENT '预测天数',
  `history_start_date` date NOT NULL COMMENT '历史统计起始日',
  `history_end_at` datetime NOT NULL COMMENT '历史统计结束时刻',
  `model_notes` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL DEFAULT NULL COMMENT '模型说明',
  `last_validated_at` datetime NULL DEFAULT NULL COMMENT '最近一次校验写入时间',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_spf_run_shop_created` (`shop_id` ASC, `created_at` ASC) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货预测运行批次';

CREATE TABLE IF NOT EXISTS `t_stock_prep_forecast_day` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `run_id` bigint NOT NULL COMMENT '批次ID',
  `stat_date` date NOT NULL COMMENT '预测自然日',
  `iso_day_of_week` tinyint NOT NULL COMMENT '周一=1…周日=7',
  `day_kind` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT '工作日/周末/调休工作日(含补班说明)等',
  `is_holiday` tinyint NOT NULL DEFAULT 0 COMMENT '是否按法定节假日休息并施加节假日系数',
  `holiday_name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL DEFAULT NULL COMMENT '节假日名称或自定义',
  `factor_holiday` decimal(8,4) NOT NULL DEFAULT 1.0000,
  `factor_weather` decimal(8,4) NOT NULL DEFAULT 1.0000,
  `factor_composite` decimal(8,4) NOT NULL DEFAULT 1.0000,
  `weather_available` tinyint NOT NULL DEFAULT 0,
  `weather_summary` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
  `weather_code` int NULL DEFAULT NULL,
  `weather_precip_prob` int NULL DEFAULT NULL COMMENT '降水概率max %',
  `weather_temp_max` decimal(5,1) NULL DEFAULT NULL COMMENT '预报最高温℃',
  `predicted_servings_sum` int NULL DEFAULT NULL COMMENT '本批次当日预测菜品份数合计',
  `actual_servings_forecast_dishes` int NULL DEFAULT NULL COMMENT '预测范围内菜品当日实际份数合计',
  `actual_servings_all_dishes` int NULL DEFAULT NULL COMMENT '当日全店订单明细销量合计',
  `actual_order_count` int NULL DEFAULT NULL COMMENT '当日成功单数',
  `daily_stat_total_amount` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结营业额',
  `daily_stat_discount_amount` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结优惠合计',
  `daily_stat_refund_amount` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结退款合计',
  `daily_stat_material_cost` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结原料成本',
  `daily_stat_settled` tinyint NULL DEFAULT NULL COMMENT '1=日结已 settled_at 非空',
  `day_validated_at` datetime NULL DEFAULT NULL COMMENT '该预测日本行校验完成时间',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_spf_day_run_date` (`run_id` ASC, `stat_date` ASC) USING BTREE,
  KEY `idx_spf_day_run` (`run_id` ASC) USING BTREE,
  CONSTRAINT `fk_spf_day_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货预测-按日';

CREATE TABLE IF NOT EXISTS `t_stock_prep_forecast_dish` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `run_id` bigint NOT NULL,
  `stat_date` date NOT NULL,
  `dish_id` int NULL DEFAULT NULL COMMENT '匹配 t_dish.id，可能为空',
  `dish_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `baseline_avg` decimal(14,4) NOT NULL DEFAULT 0.0000 COMMENT '该日星期几基线日均份数',
  `predicted_servings` int NOT NULL DEFAULT 0 COMMENT '预测备货份数',
  `actual_quantity` int NULL DEFAULT NULL COMMENT '当日该菜品实际销量',
  `validated_at` datetime NULL DEFAULT NULL COMMENT '写入实际销量的时间',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_spf_dish_run_date` (`run_id` ASC, `stat_date` ASC) USING BTREE,
  CONSTRAINT `fk_spf_dish_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货预测-按日按菜';
