-- 连锁：原料、出入库、支付方式、操作日志按门店隔离（执行前请备份）
-- 行为说明与 B 端接口约定见：docs/backend_chain_store_api.md §7.6、docs/db_chain_store_design.md、docs/openapi.yaml（v1.2.10）
-- 历史数据：原料默认归到门店 1，请按实际多店情况 UPDATE 修正 t_material.shop_id

ALTER TABLE `t_material`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '门店ID，关联 t_shop.id；NULL=未分门店的旧数据' AFTER `id`,
  ADD KEY `idx_material_shop` (`shop_id`);

UPDATE `t_material` SET `shop_id` = 1 WHERE `shop_id` IS NULL;

ALTER TABLE `t_stock_in`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '门店ID' AFTER `id`,
  ADD KEY `idx_stock_in_shop` (`shop_id`);

ALTER TABLE `t_stock_out`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '门店ID' AFTER `id`,
  ADD KEY `idx_stock_out_shop` (`shop_id`);

-- NULL = 全部门店可见（如微信、支付宝）；非 NULL 为本店自定义方式
ALTER TABLE `t_payment_method`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT 'NULL=全局；非空=仅该门店' AFTER `id`,
  ADD KEY `idx_payment_method_shop` (`shop_id`);

ALTER TABLE `t_operation_log`
  ADD COLUMN `shop_id` int NULL DEFAULT NULL COMMENT '门店ID，审计隔离' AFTER `id`,
  ADD KEY `idx_operation_log_shop` (`shop_id`);
