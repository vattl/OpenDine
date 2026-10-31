-- 外卖与真省钱（ZSQ）聚合配送对接
-- 执行前请备份；与 docs/db_migration_takeout.sql 独立

ALTER TABLE `t_takeout_delivery`
    ADD COLUMN `zsq_open_order_id` bigint NULL DEFAULT NULL COMMENT '真省钱 openOrderId（ZsqCreateOrderResult.id）' AFTER `merchant_remark`,
    ADD COLUMN `zsq_order_id` varchar(64) NULL DEFAULT NULL COMMENT '真省钱业务订单号' AFTER `zsq_open_order_id`,
    ADD COLUMN `zsq_shop_number` varchar(32) NULL DEFAULT NULL COMMENT '真省钱发单店铺编号' AFTER `zsq_order_id`,
    ADD COLUMN `zsq_parent_order_no` varchar(64) NULL DEFAULT NULL COMMENT '真省钱配送母单号' AFTER `zsq_shop_number`,
    ADD COLUMN `zsq_delivery_codes_json` varchar(256) NULL DEFAULT NULL COMMENT '已选配送渠道 deliveryCode JSON 数组' AFTER `zsq_parent_order_no`,
    ADD COLUMN `zsq_quote_json` text NULL COMMENT '最近一次询价快照 JSON' AFTER `zsq_delivery_codes_json`,
    ADD COLUMN `zsq_dispatch_json` text NULL COMMENT '最近一次发配送响应 JSON' AFTER `zsq_quote_json`,
    ADD COLUMN `zsq_delivery_send_status` int NULL DEFAULT NULL COMMENT '真省钱 deliverySendStatus 原始值' AFTER `zsq_dispatch_json`,
    ADD COLUMN `zsq_phase` varchar(32) NULL DEFAULT NULL COMMENT '归一化阶段 WAITING_RIDER/TO_SHOP/TO_USER/DELIVERED/CANCELLED' AFTER `zsq_delivery_send_status`,
    ADD COLUMN `zsq_dispatch_status` varchar(32) NOT NULL DEFAULT 'none' COMMENT 'none|pending|dispatched|failed|rider_cancelled|completed' AFTER `zsq_phase`,
    ADD COLUMN `zsq_rider_name` varchar(64) NULL DEFAULT NULL AFTER `zsq_dispatch_status`,
    ADD COLUMN `zsq_rider_phone` varchar(32) NULL DEFAULT NULL AFTER `zsq_rider_name`,
    ADD COLUMN `zsq_rider_lat` decimal(10, 6) NULL DEFAULT NULL AFTER `zsq_rider_phone`,
    ADD COLUMN `zsq_rider_lng` decimal(10, 6) NULL DEFAULT NULL AFTER `zsq_rider_lat`,
    ADD COLUMN `zsq_rider_updated_at` datetime NULL DEFAULT NULL AFTER `zsq_rider_lng`,
    ADD COLUMN `zsq_last_error` varchar(512) NULL DEFAULT NULL COMMENT '最近一次 ZSQ 错误文案' AFTER `zsq_rider_updated_at`,
    ADD COLUMN `zsq_dispatch_attempts` int NOT NULL DEFAULT 0 COMMENT '发配送尝试次数（含重发）' AFTER `zsq_last_error`,
    ADD COLUMN `zsq_liability_fee` decimal(10, 2) NULL DEFAULT NULL COMMENT '真省钱取消责任扣费（元）' AFTER `zsq_dispatch_attempts`,
    ADD COLUMN `zsq_cancel_prompt` varchar(512) NULL DEFAULT NULL COMMENT '真省钱取消提示文案' AFTER `zsq_liability_fee`,
    ADD COLUMN `zsq_cancel_json` text NULL COMMENT '真省钱取消响应 JSON' AFTER `zsq_cancel_prompt`,
    ADD INDEX `idx_takeout_zsq_open_order` (`zsq_open_order_id`),
    ADD INDEX `idx_takeout_zsq_dispatch_status` (`zsq_dispatch_status`, `dispatch_status`);

ALTER TABLE `t_shop_takeout_config`
    ADD COLUMN `zsq_enabled` tinyint NOT NULL DEFAULT 0 COMMENT '1=启用真省钱聚合配送' AFTER `remark`,
    ADD COLUMN `zsq_auto_dispatch` tinyint NOT NULL DEFAULT 1 COMMENT '1=商家接单后自动发真省钱配送' AFTER `zsq_enabled`,
    ADD COLUMN `zsq_from_address_id` bigint NULL DEFAULT NULL COMMENT '真省钱发单店铺 id，空则用默认店铺' AFTER `zsq_auto_dispatch`,
    ADD COLUMN `zsq_city_name` varchar(64) NULL DEFAULT NULL COMMENT '地址解析城市，空则取门店城市或江门市' AFTER `zsq_from_address_id`;


ALTER TABLE t_takeout_delivery
    ADD COLUMN zsq_liability_fee decimal(10,2) NULL COMMENT '真省钱取消责任扣费（元）' AFTER zsq_dispatch_attempts,
    ADD COLUMN zsq_cancel_prompt varchar(512) NULL COMMENT '真省钱取消提示文案' AFTER zsq_liability_fee,
    ADD COLUMN zsq_cancel_json text NULL COMMENT '真省钱取消响应 JSON' AFTER zsq_cancel_prompt;
