-- V015: 终端钱箱会话状态机与现金事件账本 (POS-SDC-201 ~ POS-SDC-204)
CREATE TABLE IF NOT EXISTS `t_drawer_session` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '钱箱会话自增ID',
  `session_no` VARCHAR(64) NOT NULL COMMENT '会话流水号',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `terminal_id` VARCHAR(64) NOT NULL DEFAULT 'POS-01' COMMENT '收银机终端编号',
  `drawer_code` VARCHAR(32) NOT NULL DEFAULT 'DEFAULT' COMMENT '钱箱代码',
  `state` VARCHAR(32) NOT NULL DEFAULT 'OPEN' COMMENT '状态：OPEN/CLOSING/CLOSED/REOPENED',
  `opened_by` INT NOT NULL COMMENT '开班操作人管理员ID',
  `opened_at` DATETIME NOT NULL COMMENT '开班时间',
  `opening_float_fen` INT NOT NULL DEFAULT 0 COMMENT '备用金初始金额(分)',
  `expected_cash_fen` INT DEFAULT NULL COMMENT '系统计算应有现金(分)',
  `counted_cash_fen` INT DEFAULT NULL COMMENT '实盘现金(分)',
  `variance_fen` INT DEFAULT NULL COMMENT '差额(分) = counted - expected',
  `closed_by` INT DEFAULT NULL COMMENT '关班人管理员ID',
  `closed_at` DATETIME DEFAULT NULL COMMENT '关班时间',
  `variance_reason_code` VARCHAR(64) DEFAULT NULL COMMENT '长短款差额原因代码',
  `variance_note` VARCHAR(255) DEFAULT NULL COMMENT '差额详细说明',
  `approved_by` INT DEFAULT NULL COMMENT '审批主管管理员ID',
  `approved_at` DATETIME DEFAULT NULL COMMENT '审批时间',
  `business_day` VARCHAR(16) NOT NULL COMMENT '归属营业日(YYYY-MM-DD)',
  `request_id` VARCHAR(64) DEFAULT NULL COMMENT '开班幂等请求键',
  `close_request_id` VARCHAR(64) DEFAULT NULL COMMENT '交班关箱幂等请求键',
  `version` INT NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `active_slot` INT GENERATED ALWAYS AS (CASE WHEN `state` IN ('OPEN', 'CLOSING') THEN 1 ELSE NULL END) STORED COMMENT '活动会话槽位(唯一索引)',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawer_session_no` (`session_no`),
  UNIQUE KEY `uk_active_drawer` (`shop_id`, `terminal_id`, `drawer_code`, `active_slot`),
  KEY `idx_drawer_shop_day` (`shop_id`, `business_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='终端钱箱会话' ROW_FORMAT=DYNAMIC;

CREATE TABLE IF NOT EXISTS `t_cash_movement` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '现金动作流水ID',
  `movement_no` VARCHAR(64) NOT NULL COMMENT '动作流水号',
  `drawer_session_id` BIGINT NOT NULL COMMENT '关联钱箱会话ID',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `movement_type` VARCHAR(32) NOT NULL COMMENT '类型：OPENING_FLOAT/CASH_SALE/CASH_REFUND/CASH_IN/CASH_OUT/CASH_DROP/COUNT/ADJUSTMENT/NO_SALE',
  `amount_fen` INT NOT NULL COMMENT '金额(分)，流入为正，流出为负',
  `current_balance_fen` INT NOT NULL DEFAULT 0 COMMENT '动作发生后推导钱箱当前现金余额(分)',
  `reason_code` VARCHAR(64) DEFAULT NULL COMMENT '原因代码',
  `remark` VARCHAR(255) DEFAULT NULL COMMENT '备注',
  `operator_id` INT NOT NULL COMMENT '经办人管理员ID',
  `approver_id` INT DEFAULT NULL COMMENT '审批人管理员ID',
  `order_id` BIGINT DEFAULT NULL COMMENT '关联订单ID',
  `order_no` VARCHAR(64) DEFAULT NULL COMMENT '关联订单号',
  `payment_ledger_id` BIGINT DEFAULT NULL COMMENT '关联支付台账ID',
  `request_id` VARCHAR(64) DEFAULT NULL COMMENT '幂等请求键',
  `occurred_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '动作发生时间',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '落账时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_cash_movement_no` (`movement_no`),
  KEY `idx_cm_session` (`drawer_session_id`),
  KEY `idx_cm_shop_time` (`shop_id`, `occurred_at`),
  KEY `idx_cm_order` (`shop_id`, `order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='不可表现金动作账本' ROW_FORMAT=DYNAMIC;

-- 给 t_shift 补充钱箱与商用化审计关联字段（MySQL兼容幂等添加）
SET @dbname = DATABASE();
SET @tablename = 't_shift';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'drawer_session_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `drawer_session_id` BIGINT DEFAULT NULL COMMENT ''关联钱箱会话ID'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'terminal_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `terminal_id` VARCHAR(64) DEFAULT NULL COMMENT ''终端编号'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'state') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `state` VARCHAR(32) DEFAULT ''OPEN'' COMMENT ''状态：OPEN/CLOSED'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'business_day') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `business_day` VARCHAR(16) DEFAULT NULL COMMENT ''归属营业日(YYYY-MM-DD)'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'version') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `version` INT DEFAULT 1 COMMENT ''乐观锁版本'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

