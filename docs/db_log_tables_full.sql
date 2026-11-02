-- ============================================================
-- 日志模块完整建表 SQL（重建模式）
-- 覆盖 6 张日志相关表：DROP TABLE IF EXISTS + CREATE TABLE
-- ⚠ 警告：执行将【清空全部日志数据】，请确认可接受后再执行
-- ⚠ 注意：t_report_export_job 同时承载【报表导出】与【日志导出/归档检索】任务状态，
--         重建会丢失进行中的导出/归档任务，建议确认无进行中任务后执行
-- 幂等：可重复执行；字符集 utf8mb4 / utf8mb4_general_ci
-- ============================================================
SET NAMES utf8mb4;

-- ------------------------------------------------------------
-- 1) 关键操作审计日志（AuditLogAspect / SecurityAuditService / 收银桌台审计）
--    id 由应用雪花 ID 显式写入；AUTO_INCREMENT 兼容 CashierTableAudit(IdType.AUTO)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_operation_log`;
CREATE TABLE `t_operation_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，审计隔离',
  `module` varchar(32) NOT NULL COMMENT 'order/dish/price/daily等',
  `action` varchar(64) NOT NULL COMMENT 'delete_order/change_price/un_checkout等',
  `target_id` varchar(64) DEFAULT NULL COMMENT '订单号或ID',
  `admin_id` int(11) DEFAULT NULL,
  `ip` varchar(64) DEFAULT NULL,
  `request_snapshot` text COMMENT '请求关键参数',
  `source_table` varchar(50) DEFAULT NULL COMMENT '源桌号',
  `target_table` varchar(50) DEFAULT NULL COMMENT '目标桌号；非并台为空',
  `order_nos` text COMMENT '涉及订单号 JSON 数组',
  `before_state` text COMMENT '操作前桌台/订单状态 JSON',
  `after_state` text COMMENT '操作后桌台/订单状态 JSON',
  `result_status` varchar(16) DEFAULT NULL COMMENT 'SUCCESS/REJECTED/ROLLED_BACK',
  `result_code` int(11) DEFAULT NULL COMMENT '接口业务码',
  `reason` varchar(255) DEFAULT NULL COMMENT '成功说明或拒绝/回滚原因（不含敏感信息）',
  `request_key` varchar(128) DEFAULT NULL COMMENT 'Idempotency-Key/X-Request-ID/trace 标识',
  `request_fingerprint` char(64) DEFAULT NULL COMMENT '动作和桌号参数 SHA-256，用于防止幂等键误复用',
  `trace_id` varchar(128) DEFAULT NULL COMMENT '链路追踪标识',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_log_shop_created` (`shop_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='关键操作日志';

-- ------------------------------------------------------------
-- 2) 订单操作日志（收银端 + C 端：下单/取消/加菜/支付/退款）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_order_log`;
CREATE TABLE `t_order_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，审计隔离',
  `order_no` varchar(100) DEFAULT NULL COMMENT '订单号',
  `action` varchar(64) NOT NULL COMMENT 'create/cancel/add_dish/pay/refund/checkout等',
  `operator_type` varchar(32) DEFAULT NULL COMMENT 'openid/admin_id/system/device',
  `operator_id` varchar(64) DEFAULT NULL COMMENT '操作人ID',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_log_shop_created` (`shop_id`, `created_at`),
  KEY `idx_order_log_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='订单操作日志';

-- ------------------------------------------------------------
-- 3) 菜品库存变动流水（DishShopStockServiceImpl 扣减/回退/盘点）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_dish_stock_log`;
CREATE TABLE `t_dish_stock_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT '门店ID',
  `dish_id` int NOT NULL COMMENT '菜品ID',
  `dish_name` varchar(128) DEFAULT NULL COMMENT '菜品名称',
  `order_no` varchar(64) DEFAULT NULL COMMENT '关联订单号',
  `detail_id` int DEFAULT NULL COMMENT '关联订单明细ID',
  `change_type` varchar(32) NOT NULL COMMENT '变动类型：CREATE_ORDER/ADD_DISH/CANCEL_ORDER/REFUND_RESTORE/REFUND_NO_RESTORE/REFUND_OUT_OF_STOCK/ADMIN_MANUAL/KDS_LACK',
  `delta` int NOT NULL COMMENT '变动数量(+增/-减/0不变)',
  `stock_before` int DEFAULT NULL COMMENT '变动前库存',
  `stock_after` int DEFAULT NULL COMMENT '变动后库存',
  `operator_id` varchar(64) DEFAULT NULL COMMENT '操作人/终端',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注/退菜原因',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shop_dish_time` (`shop_id`, `dish_id`, `created_at`),
  KEY `idx_order_no` (`order_no`),
  KEY `idx_stock_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='菜品库存变动流水日志表';

-- ------------------------------------------------------------
-- 4) KDS 操作审计日志（后厨设备：催菜/撤销/加急/退菜/沽清等）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_kds_operation_log`;
CREATE TABLE `t_kds_operation_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `device_id` bigint DEFAULT NULL,
  `order_id` int NOT NULL,
  `detail_id` int DEFAULT NULL,
  `ticket_id` bigint DEFAULT NULL,
  `operation_type` varchar(32) NOT NULL COMMENT 'advance/revoke/rush/refund/lack/hold/release',
  `from_queue` varchar(32) DEFAULT NULL,
  `to_queue` varchar(32) DEFAULT NULL,
  `quantity` int NOT NULL DEFAULT '0',
  `request_id` varchar(64) DEFAULT NULL,
  `operator_type` varchar(16) NOT NULL DEFAULT 'device' COMMENT 'device/admin/pos',
  `operator_id` bigint DEFAULT NULL,
  `result_code` varchar(32) NOT NULL DEFAULT '0',
  `result_msg` varchar(255) DEFAULT NULL,
  `payload_json` json DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_op_shop_time` (`shop_id`, `created_at`),
  KEY `idx_kds_op_detail` (`detail_id`, `created_at`),
  KEY `idx_kds_op_ticket` (`ticket_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS操作审计日志';

-- ------------------------------------------------------------
-- 5) KDS 复制死信人工介入审计（retry/replace/discard 动作留痕）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_kds_replication_dead_letter_audit`;
CREATE TABLE `t_kds_replication_dead_letter_audit` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `event_id` varchar(128) NOT NULL,
  `action` varchar(20) NOT NULL COMMENT 'retry/replace/discard',
  `reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `operator_admin_id` int DEFAULT NULL,
  `operator_subject` varchar(128) NOT NULL,
  `trace_id` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_dead_letter_audit` (`shop_id`, `event_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditable dead-letter operator actions';

-- ------------------------------------------------------------
-- 6) 报表/日志导出与归档检索任务表（job_type 区分报表与日志任务）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_report_export_job`;
CREATE TABLE `t_report_export_job` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '任务ID',
  `shop_id` int NOT NULL COMMENT '门店ID t_shop.id（隔离维度）',
  `job_type` varchar(32) NOT NULL COMMENT '任务类型：REPORT_EXPORT/LOG_EXPORT/ARCHIVE_SEARCH',
  `report_type` varchar(64) DEFAULT NULL COMMENT '报表类型：daily/weekly/monthly；日志类任务为 log',
  `filters_json` text COMMENT '筛选条件 JSON（报表 filters / 日志查询条件 + purpose）',
  `format` varchar(16) NOT NULL DEFAULT 'csv' COMMENT '导出格式：csv/xlsx（当前实现仅 csv）',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT '状态：PENDING/RUNNING/DONE/FAILED',
  `file_name` varchar(255) DEFAULT NULL COMMENT '生成文件名（服务端 ./data/exports 目录下）',
  `download_token` varchar(64) DEFAULT NULL COMMENT '32 位随机下载令牌（完成时生成）',
  `token_expires_at` datetime DEFAULT NULL COMMENT '下载令牌过期时间（生成后 15 分钟）',
  `result_summary_json` text COMMENT '结果摘要 JSON（归档查询存命中数/窗口/提示）',
  `error` varchar(512) DEFAULT NULL COMMENT '失败原因或过期提示（如 download link expired）',
  `created_by` int DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_shop_created` (`shop_id`, `created_at`),
  KEY `idx_shop_type_status` (`shop_id`, `job_type`, `status`),
  KEY `idx_token` (`download_token`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='报表/日志导出与归档检索任务';
