-- V017: 商业级渠道对账单批次、明细与三层差异处理单
-- 关联设计规范：POS-SDC-401、POS-SDC-402

-- 1. 渠道对账单导入批次表
CREATE TABLE IF NOT EXISTS `t_channel_statement_batch` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '批次自增主键',
    `batch_no` VARCHAR(64) NOT NULL COMMENT '批次业务流水号，格式 BAT-yyyyMMdd-XXXXXX',
    `shop_id` INT NOT NULL COMMENT '门店ID',
    `channel` VARCHAR(32) NOT NULL COMMENT '渠道类型: WECHAT/ALIPAY/UNIONPAY/OTHER',
    `statement_date` DATE NOT NULL COMMENT '账单所属日期 (yyyy-MM-dd)',
    `file_name` VARCHAR(255) NOT NULL COMMENT '原始文件名',
    `file_hash_sha256` CHAR(64) NOT NULL COMMENT '文件内容 SHA-256 摘要，用于防重复导入',
    `total_count` INT NOT NULL DEFAULT 0 COMMENT '解析交易笔数',
    `total_amount_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '交易总金额（分）',
    `fee_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '手续费总额（分）',
    `net_amount_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '结算净额（分）',
    `status` VARCHAR(32) NOT NULL DEFAULT 'PARSED' COMMENT '状态: PARSED(已解析)/FAILED(解析失败)',
    `error_summary` TEXT DEFAULT NULL COMMENT '解析错误摘要/忽略行日志',
    `imported_by` INT DEFAULT NULL COMMENT '导入操作人管理员ID',
    `imported_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '导入时间',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    UNIQUE KEY `uk_statement_file_hash` (`shop_id`, `file_hash_sha256`),
    INDEX `idx_statement_batch_day` (`shop_id`, `statement_date`),
    INDEX `idx_statement_batch_no` (`batch_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='渠道对账单导入批次表';

-- 2. 渠道对账单明细表
CREATE TABLE IF NOT EXISTS `t_channel_statement_entry` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '明细自增主键',
    `batch_id` BIGINT NOT NULL COMMENT '所属导入批次ID',
    `shop_id` INT NOT NULL COMMENT '门店ID',
    `channel` VARCHAR(32) NOT NULL COMMENT '渠道类型: WECHAT/ALIPAY',
    `channel_trade_no` VARCHAR(128) NOT NULL COMMENT '第三方渠道流水号/微信支付订单号/支付宝交易号',
    `merchant_order_no` VARCHAR(128) NOT NULL COMMENT '商户订单号/系统单号',
    `entry_type` VARCHAR(32) NOT NULL COMMENT '交易类型: PAYMENT(收款)/REFUND(退款)',
    `amount_fen` INT NOT NULL COMMENT '交易金额（分，正数）',
    `fee_fen` INT NOT NULL DEFAULT 0 COMMENT '手续费（分）',
    `net_amount_fen` INT NOT NULL DEFAULT 0 COMMENT '应结净额（分）',
    `trade_time` DATETIME NOT NULL COMMENT '渠道交易发生时间',
    `matched_ledger_id` BIGINT DEFAULT NULL COMMENT '匹配的内部支付台账ID',
    `match_status` VARCHAR(32) NOT NULL DEFAULT 'UNMATCHED' COMMENT '匹配状态: MATCHED(已对平)/UNMATCHED(未匹配)/AMOUNT_MISMATCH(金额不符)/TIMING_DIFFERENCE(跨期时间差)',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    INDEX `idx_statement_entry_batch` (`batch_id`),
    INDEX `idx_statement_entry_order` (`shop_id`, `merchant_order_no`),
    INDEX `idx_statement_entry_trade` (`shop_id`, `channel_trade_no`),
    INDEX `idx_statement_entry_status` (`shop_id`, `match_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='渠道对账单明细表';

-- 3. 对账差异处理单表
CREATE TABLE IF NOT EXISTS `t_reconciliation_case` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '自增主键',
    `case_no` VARCHAR(64) NOT NULL COMMENT '差异单号，格式 CASE-yyyyMMdd-XXXXXX',
    `shop_id` INT NOT NULL COMMENT '门店ID',
    `business_day` DATE NOT NULL COMMENT '营业日 (yyyy-MM-dd)',
    `channel` VARCHAR(32) NOT NULL COMMENT '渠道类型: WECHAT/ALIPAY/INTERNAL',
    `layer` INT NOT NULL COMMENT '差异层级: 1(订单与内部台账)/2(内部台账与渠道账单)/3(渠道账单与资金结算)',
    `discrepancy_type` VARCHAR(64) NOT NULL COMMENT '差异类型: ORDER_LEDGER_MISMATCH/INTERNAL_MISSING/CHANNEL_MISSING/AMOUNT_MISMATCH/DUPLICATE_TRANSACTION/REFUND_STATUS_MISMATCH/FEE_MISMATCH/TIMING_DIFFERENCE',
    `status` VARCHAR(32) NOT NULL DEFAULT 'OPEN' COMMENT '状态: OPEN(待处理)/INVESTIGATING(调查中)/ADJUSTED(已调账)/WRITTEN_OFF(已核销)/CLOSED(已关闭)',
    `order_id` INT DEFAULT NULL COMMENT '关联订单ID',
    `ledger_id` BIGINT DEFAULT NULL COMMENT '关联内部支付台账ID',
    `statement_entry_id` BIGINT DEFAULT NULL COMMENT '关联渠道对账明细ID',
    `internal_amount_fen` INT NOT NULL DEFAULT 0 COMMENT '内部记录金额（分）',
    `channel_amount_fen` INT NOT NULL DEFAULT 0 COMMENT '外部渠道金额（分）',
    `difference_fen` INT NOT NULL DEFAULT 0 COMMENT '差异金额（分，内部 - 外部）',
    `reason` VARCHAR(255) DEFAULT NULL COMMENT '差异初步原因',
    `resolution_note` TEXT DEFAULT NULL COMMENT '处置说明与结论',
    `responsible_person` VARCHAR(64) DEFAULT NULL COMMENT '责任人姓名/工号',
    `assigned_to` INT DEFAULT NULL COMMENT '分派跟进管理员ID',
    `resolved_by` INT DEFAULT NULL COMMENT '平账/关闭人管理员ID',
    `resolved_at` DATETIME DEFAULT NULL COMMENT '处置完成时间',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    UNIQUE KEY `uk_reconciliation_case_no` (`case_no`),
    INDEX `idx_reconciliation_case_day` (`shop_id`, `business_day`, `status`),
    INDEX `idx_reconciliation_case_type` (`shop_id`, `discrepancy_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='对账差异处理单表';
