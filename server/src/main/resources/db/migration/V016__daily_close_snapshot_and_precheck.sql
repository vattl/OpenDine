-- V016: 营业日关账快照与日结后调整账本 (POS-SDC-301 ~ POS-SDC-304)

CREATE TABLE IF NOT EXISTS `t_daily_close_snapshot` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '日结快照自增ID',
  `snapshot_no` VARCHAR(64) NOT NULL COMMENT '日结快照编号 (DSN...)',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `business_day` VARCHAR(16) NOT NULL COMMENT '营业日 (YYYY-MM-DD)',
  `window_start` DATETIME NOT NULL COMMENT '营业窗口开始时间',
  `window_end` DATETIME NOT NULL COMMENT '营业窗口截止时间',
  `state` VARCHAR(32) NOT NULL DEFAULT 'CLOSED' COMMENT '状态：PREVIEW/CLOSING/CLOSED/REOPENED',
  `cutoff_ledger_id` BIGINT DEFAULT NULL COMMENT '账本截止水位ID',
  `cutoff_movement_id` BIGINT DEFAULT NULL COMMENT '现金动作截止水位ID',
  `cutoff_order_id` BIGINT DEFAULT NULL COMMENT '订单截止水位ID',
  `total_sales_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '总营业额(分)',
  `discount_amount_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '优惠折扣总额(分)',
  `refund_amount_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '退款总额(分)',
  `net_sales_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '净营业实收(分)',
  `order_count` INT NOT NULL DEFAULT 0 COMMENT '成交订单总数',
  `drawer_session_count` INT NOT NULL DEFAULT 0 COMMENT '钱箱班次数量',
  `total_cash_variance_fen` INT NOT NULL DEFAULT 0 COMMENT '钱箱现金长短款累计(分)',
  `member_recharge_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '会员储值本金(分)',
  `channel_breakdown_json` TEXT DEFAULT NULL COMMENT '各支付渠道实收明细JSON',
  `drawer_summary_json` TEXT DEFAULT NULL COMMENT '钱箱流水公式与现金盘点汇总JSON',
  `snapshot_hash` VARCHAR(64) DEFAULT NULL COMMENT '不可变数据SHA-256摘要防篡改哈希',
  `operator_id` INT NOT NULL COMMENT '日结经办人ID',
  `reviewer_id` INT DEFAULT NULL COMMENT '日结复核/审批人ID',
  `reopened_at` DATETIME DEFAULT NULL COMMENT '重开时间',
  `reopened_by` INT DEFAULT NULL COMMENT '重开操作人ID',
  `reopen_reason` VARCHAR(255) DEFAULT NULL COMMENT '重开原因',
  `closed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '关账完成时间',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_snapshot_no` (`snapshot_no`),
  UNIQUE KEY `uk_shop_business_day` (`shop_id`, `business_day`),
  KEY `idx_dcs_shop_day` (`shop_id`, `business_day`, `state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='营业日关账不可变快照主表' ROW_FORMAT=DYNAMIC;

CREATE TABLE IF NOT EXISTS `t_daily_adjustment` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '日结后调整自增ID',
  `adjustment_no` VARCHAR(64) NOT NULL COMMENT '调整单号 (ADJ...)',
  `snapshot_id` BIGINT NOT NULL COMMENT '关联日结快照ID',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `business_day` VARCHAR(16) NOT NULL COMMENT '关联营业日 (YYYY-MM-DD)',
  `adjustment_type` VARCHAR(32) NOT NULL COMMENT '调整类型：POST_CLOSE_REFUND/POST_CLOSE_CASH/MANUAL_ADJUSTMENT',
  `amount_fen` INT NOT NULL COMMENT '调整金额(分)，退款为负，补录为正',
  `order_id` BIGINT DEFAULT NULL COMMENT '关联订单ID',
  `payment_ledger_id` BIGINT DEFAULT NULL COMMENT '关联支付流水ID',
  `reason` VARCHAR(255) NOT NULL COMMENT '调整原因',
  `operator_id` INT NOT NULL COMMENT '经办人ID',
  `approved_by` INT DEFAULT NULL COMMENT '审批人ID',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '调整记录时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_daily_adj_no` (`adjustment_no`),
  KEY `idx_adj_snapshot` (`snapshot_id`),
  KEY `idx_adj_shop_day` (`shop_id`, `business_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='日结后调整台账' ROW_FORMAT=DYNAMIC;

-- 给 t_daily_stat 添加快照外键关联（MySQL兼容幂等添加）
SET @dbname = DATABASE();
SET @tablename = 't_daily_stat';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'snapshot_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_daily_stat` ADD COLUMN `snapshot_id` BIGINT DEFAULT NULL COMMENT ''关联不可变日结快照ID'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

