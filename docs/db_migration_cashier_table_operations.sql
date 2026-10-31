-- 商业收银桌台操作：审计、幂等与锁查询索引（MySQL 8.0+）
-- 执行前请确认 t_table 已有 uk_table_shop_number(shop_id, number)。

SET NAMES utf8mb4;

ALTER TABLE `t_operation_log`
  ADD COLUMN `source_table` varchar(50) NULL COMMENT '源桌号' AFTER `request_snapshot`,
  ADD COLUMN `target_table` varchar(50) NULL COMMENT '目标桌号；非并台为空' AFTER `source_table`,
  ADD COLUMN `order_nos` text NULL COMMENT '涉及订单号 JSON 数组' AFTER `target_table`,
  ADD COLUMN `before_state` text NULL COMMENT '操作前桌台/订单状态 JSON' AFTER `order_nos`,
  ADD COLUMN `after_state` text NULL COMMENT '操作后桌台/订单状态 JSON' AFTER `before_state`,
  ADD COLUMN `result_status` varchar(16) NULL COMMENT 'SUCCESS/REJECTED/ROLLED_BACK' AFTER `after_state`,
  ADD COLUMN `result_code` int NULL COMMENT '接口业务码' AFTER `result_status`,
  ADD COLUMN `reason` varchar(255) NULL COMMENT '成功说明或拒绝/回滚原因（不含敏感信息）' AFTER `result_code`,
  ADD COLUMN `request_key` varchar(128) NULL COMMENT 'Idempotency-Key/X-Request-ID/trace 标识' AFTER `reason`,
  ADD COLUMN `request_fingerprint` char(64) NULL COMMENT '动作和桌号参数 SHA-256，用于防止幂等键误复用' AFTER `request_key`,
  ADD COLUMN `trace_id` varchar(128) NULL COMMENT '链路追踪标识' AFTER `request_fingerprint`,
  ADD UNIQUE KEY `uk_operation_log_cashier_idem`
    (`shop_id`, `module`, `action`, `request_key`),
  ADD KEY `idx_operation_log_cashier_trace` (`trace_id`),
  ADD KEY `idx_operation_log_cashier_table_time`
    (`shop_id`, `source_table`, `created_at`);

ALTER TABLE `t_order`
  ADD KEY `idx_order_shop_table_status_id`
    (`shop_id`, `table_number`, `transac_status`, `id`);
