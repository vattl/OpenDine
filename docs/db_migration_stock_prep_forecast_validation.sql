-- 备货预测「对账 / 训练标签」列追加（仅适用于已按旧版 db_migration_stock_prep_forecast.sql 建表、尚未含下列列的库）。
-- 新版建表脚本已合并这些列时，可跳过本文件。

ALTER TABLE `t_stock_prep_forecast_dish`
  ADD COLUMN `actual_quantity` int NULL DEFAULT NULL COMMENT '当日该菜品实际销量(订单明细汇总)' AFTER `predicted_servings`,
  ADD COLUMN `validated_at` datetime NULL DEFAULT NULL COMMENT '写入实际销量的时间' AFTER `actual_quantity`;

ALTER TABLE `t_stock_prep_forecast_day`
  ADD COLUMN `predicted_servings_sum` int NULL DEFAULT NULL COMMENT '本批次当日预测菜品份数合计(预测范围内)' AFTER `weather_temp_max`,
  ADD COLUMN `actual_servings_forecast_dishes` int NULL DEFAULT NULL COMMENT '预测范围内菜品当日实际份数合计' AFTER `predicted_servings_sum`,
  ADD COLUMN `actual_servings_all_dishes` int NULL DEFAULT NULL COMMENT '当日全店订单明细销量合计(所有菜品)' AFTER `actual_servings_forecast_dishes`,
  ADD COLUMN `actual_order_count` int NULL DEFAULT NULL COMMENT '当日成功单数' AFTER `actual_servings_all_dishes`,
  ADD COLUMN `daily_stat_total_amount` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结表营业额 t_daily_stat.total_amount' AFTER `actual_order_count`,
  ADD COLUMN `daily_stat_discount_amount` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结优惠合计' AFTER `daily_stat_total_amount`,
  ADD COLUMN `daily_stat_refund_amount` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结退款合计' AFTER `daily_stat_discount_amount`,
  ADD COLUMN `daily_stat_material_cost` decimal(12, 2) NULL DEFAULT NULL COMMENT '日结原料成本' AFTER `daily_stat_refund_amount`,
  ADD COLUMN `daily_stat_settled` tinyint NULL DEFAULT NULL COMMENT '1=日结已 settled_at 非空' AFTER `daily_stat_material_cost`,
  ADD COLUMN `day_validated_at` datetime NULL DEFAULT NULL COMMENT '该预测日本行校验完成时间' AFTER `daily_stat_settled`;

ALTER TABLE `t_stock_prep_forecast_run`
  ADD COLUMN `last_validated_at` datetime NULL DEFAULT NULL COMMENT '最近一次校验写入时间' AFTER `model_notes`;
