-- WI-023: commercial accounts-receivable core.
CREATE TABLE IF NOT EXISTS `t_receivable_account` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `account_no` VARCHAR(64) NOT NULL,
  `merchant_id` VARCHAR(64) NOT NULL DEFAULT '1',
  `scope_type` VARCHAR(20) NOT NULL DEFAULT 'SHOP',
  `shop_id` INT DEFAULT NULL,
  `customer_type` VARCHAR(20) NOT NULL DEFAULT 'PERSON',
  `customer_name` VARCHAR(120) NOT NULL,
  `contact_name` VARCHAR(80) DEFAULT NULL,
  `contact_phone` VARCHAR(32) DEFAULT NULL,
  `tax_no` VARCHAR(64) DEFAULT NULL,
  `credit_limit_fen` BIGINT NOT NULL DEFAULT 0,
  `outstanding_fen` BIGINT NOT NULL DEFAULT 0,
  `payment_terms_days` INT NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  `notes` VARCHAR(500) DEFAULT NULL,
  `version` INT NOT NULL DEFAULT 1,
  `created_by` INT DEFAULT NULL,
  `updated_by` INT DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_receivable_account_no` (`merchant_id`, `account_no`),
  KEY `idx_receivable_account_scope` (`merchant_id`, `shop_id`, `scope_type`, `status`),
  KEY `idx_receivable_account_phone` (`merchant_id`, `contact_phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='应收客户授信账户';

CREATE TABLE IF NOT EXISTS `t_receivable_claim` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `claim_no` VARCHAR(64) NOT NULL,
  `request_id` VARCHAR(128) NOT NULL,
  `active_key` VARCHAR(255) DEFAULT NULL COMMENT '同订单活动应收唯一键；撤销后释放',
  `merchant_id` VARCHAR(64) NOT NULL DEFAULT '1',
  `shop_id` INT NOT NULL,
  `account_id` BIGINT NOT NULL,
  `order_id` BIGINT DEFAULT NULL,
  `order_no` VARCHAR(100) NOT NULL,
  `original_amount_fen` BIGINT NOT NULL,
  `outstanding_fen` BIGINT NOT NULL,
  `due_date` DATETIME NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  `note` VARCHAR(500) DEFAULT NULL,
  `version` INT NOT NULL DEFAULT 1,
  `charged_by` INT DEFAULT NULL,
  `charged_at` DATETIME NOT NULL,
  `settled_at` DATETIME DEFAULT NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_receivable_claim_no` (`merchant_id`, `claim_no`),
  UNIQUE KEY `uk_receivable_claim_request` (`merchant_id`, `request_id`),
  UNIQUE KEY `uk_receivable_claim_active` (`active_key`),
  KEY `idx_receivable_claim_account` (`merchant_id`, `account_id`, `status`, `due_date`),
  KEY `idx_receivable_claim_shop` (`merchant_id`, `shop_id`, `status`, `due_date`),
  KEY `idx_receivable_claim_order` (`merchant_id`, `shop_id`, `order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单级应收单';

CREATE TABLE IF NOT EXISTS `t_receivable_ledger` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `ledger_no` VARCHAR(64) NOT NULL,
  `request_id` VARCHAR(128) NOT NULL,
  `merchant_id` VARCHAR(64) NOT NULL DEFAULT '1',
  `shop_id` INT NOT NULL,
  `account_id` BIGINT NOT NULL,
  `claim_id` BIGINT NOT NULL,
  `order_id` BIGINT DEFAULT NULL,
  `order_no` VARCHAR(100) NOT NULL,
  `entry_type` VARCHAR(20) NOT NULL,
  `amount_fen` BIGINT NOT NULL COMMENT 'CHARGE正数；COLLECTION/REVERSAL/WRITE_OFF负数',
  `channel` VARCHAR(32) DEFAULT NULL,
  `drawer_session_id` BIGINT DEFAULT NULL,
  `operator_id` INT DEFAULT NULL,
  `business_day` VARCHAR(10) NOT NULL,
  `note` VARCHAR(500) DEFAULT NULL,
  `original_ledger_id` BIGINT DEFAULT NULL,
  `occurred_at` DATETIME NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_receivable_ledger_no` (`merchant_id`, `ledger_no`),
  UNIQUE KEY `uk_receivable_ledger_request` (`merchant_id`, `request_id`),
  KEY `idx_receivable_ledger_window` (`merchant_id`, `shop_id`, `occurred_at`, `id`),
  KEY `idx_receivable_ledger_account` (`merchant_id`, `account_id`, `id`),
  KEY `idx_receivable_ledger_claim` (`claim_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='不可变应收账款流水';

SET @dbname = DATABASE();
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN cutoff_receivable_ledger_id BIGINT NOT NULL DEFAULT 0 COMMENT ''应收流水截止水位''',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='cutoff_receivable_ledger_id');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN receivable_charged_fen BIGINT NOT NULL DEFAULT 0',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='receivable_charged_fen');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN receivable_collected_fen BIGINT NOT NULL DEFAULT 0',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='receivable_collected_fen');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN receivable_writeoff_fen BIGINT NOT NULL DEFAULT 0',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='receivable_writeoff_fen');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN receivable_outstanding_fen BIGINT NOT NULL DEFAULT 0',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='receivable_outstanding_fen');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN total_collections_fen BIGINT NOT NULL DEFAULT 0',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='total_collections_fen');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

INSERT IGNORE INTO `t_permission` (`permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
('receivable:view', '查看应收', 'receivable', '查看账户、应收单、流水和账龄', 91),
('receivable:manage', '管理应收账户', 'receivable', '创建、修改、暂停和关闭授信账户', 92),
('receivable:merchant_manage', '管理商户共享应收账户', 'receivable', '创建和维护跨门店共享授信账户', 93),
('receivable:charge', '订单挂账', 'receivable', '将未结订单转为应收', 94),
('receivable:collect', '应收回款', 'receivable', '登记并核销真实回款', 95),
('receivable:writeoff', '坏账与撤销', 'receivable', '撤销未回款应收或核销坏账', 96);

INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT r.id, p.id FROM t_role r JOIN t_permission p
WHERE r.role_code='boss' AND p.permission_code LIKE 'receivable:%';
INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT r.id, p.id FROM t_role r JOIN t_permission p
WHERE r.role_code='store_manager' AND p.permission_code IN
('receivable:view','receivable:manage','receivable:charge','receivable:collect','receivable:writeoff');
INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT r.id, p.id FROM t_role r JOIN t_permission p
WHERE r.role_code='cashier' AND p.permission_code IN ('receivable:view','receivable:charge','receivable:collect');

INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`) VALUES
('*', '/cashier/receivables/eligible-accounts', 'receivable:view'),
('*', '/cashier/receivables/charges', 'receivable:charge'),
('*', '/cashier/receivables/claims', 'receivable:view'),
('*', '/cashier/receivables/claims/*', 'receivable:view'),
('*', '/cashier/receivables/claims/*/collections', 'receivable:collect'),
('*', '/admin/receivables/accounts', 'receivable:view|receivable:manage'),
('*', '/admin/receivables/accounts/*', 'receivable:view|receivable:manage'),
('*', '/admin/receivables/accounts/*/status', 'receivable:manage'),
('*', '/admin/receivables/accounts/*/close', 'receivable:manage'),
('*', '/admin/receivables/accounts/*/statement', 'receivable:view'),
('*', '/admin/receivables/claims', 'receivable:view'),
('*', '/admin/receivables/claims/*/collections', 'receivable:collect'),
('*', '/admin/receivables/claims/*/reverse', 'receivable:writeoff'),
('*', '/admin/receivables/claims/*/write-off', 'receivable:writeoff'),
('*', '/admin/receivables/aging', 'receivable:view')
ON DUPLICATE KEY UPDATE `permission_code`=VALUES(`permission_code`);
