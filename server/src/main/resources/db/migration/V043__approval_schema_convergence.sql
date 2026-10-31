-- WI-061: approval schema convergence across empty, legacy and partially migrated databases.
-- Idempotently ensures t_access_approval and t_access_approval_rate_limit exist with full latest columns.

-- 1. Ensure t_access_approval table exists (for clean installs or databases missing V020).
CREATE TABLE IF NOT EXISTS `t_access_approval` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `approval_no` VARCHAR(64) NOT NULL COMMENT '审批唯一流水号',
  `permission_code` VARCHAR(100) NOT NULL COMMENT '需要授权的目标权限码',
  `operator_id` INT NOT NULL COMMENT '操作人管理员ID',
  `authorizer_id` INT NOT NULL COMMENT '授权人(店长)管理员ID',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `biz_type` VARCHAR(50) NOT NULL COMMENT '业务类型: ORDER, REFUND, CASH_DRAWER等',
  `biz_id` VARCHAR(100) NOT NULL COMMENT '业务对象唯一标识 (如订单号)',
  `amount` DECIMAL(12,2) DEFAULT NULL COMMENT '申请涉及的业务金额',
  `reason` VARCHAR(500) NOT NULL COMMENT '授权原因',
  `auth_method` VARCHAR(30) NOT NULL COMMENT '授权认证方式: PASSWORD, PIN, SESSION',
  `status` VARCHAR(20) NOT NULL DEFAULT 'APPROVED' COMMENT '状态: PENDING, APPROVED, CONSUMED, EXPIRED, REVOKED, REJECTED',
  `token_hash` CHAR(64) NOT NULL COMMENT '短期授权Token的SHA-256哈希值',
  `binding_version` INT NOT NULL DEFAULT 1 COMMENT '审批上下文绑定策略版本: 1兼容, 2严格',
  `token_value` VARCHAR(512) DEFAULT NULL COMMENT '二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌',
  `max_amount` DECIMAL(12,2) DEFAULT NULL COMMENT '授权允许的最大金额上限',
  `expires_at` DATETIME NOT NULL COMMENT 'Token有效截止时间',
  `consumed_at` DATETIME DEFAULT NULL COMMENT 'Token核销消费时间',
  `request_id` VARCHAR(128) DEFAULT NULL COMMENT '客户端幂等请求标识',
  `terminal_id` VARCHAR(100) DEFAULT NULL COMMENT '终端编号',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_approval_no` (`approval_no`),
  KEY `idx_token_hash` (`token_hash`),
  KEY `idx_operator` (`operator_id`),
  KEY `idx_biz` (`biz_type`, `biz_id`),
  KEY `idx_expire` (`status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限临时审批与授权令牌表' ROW_FORMAT=DYNAMIC;

-- 2. Idempotently converge columns for existing t_access_approval tables (where V020 ran but V037/V038 did not).
SET @ddl_binding = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND table_name = 't_access_approval'
     AND column_name = 'binding_version') = 0,
  'ALTER TABLE `t_access_approval` ADD COLUMN `binding_version` int NOT NULL DEFAULT 1 COMMENT ''审批上下文绑定策略版本: 1兼容, 2严格'' AFTER `token_hash`',
  'SELECT 1'
);
PREPARE stmt_binding FROM @ddl_binding;
EXECUTE stmt_binding;
DEALLOCATE PREPARE stmt_binding;

SET @ddl_token_val = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND table_name = 't_access_approval'
     AND column_name = 'token_value') = 0,
  'ALTER TABLE `t_access_approval` ADD COLUMN `token_value` varchar(512) NULL COMMENT ''二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌'' AFTER `token_hash`',
  'ALTER TABLE `t_access_approval` MODIFY COLUMN `token_value` varchar(512) NULL COMMENT ''二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌'''
);
PREPARE stmt_token_val FROM @ddl_token_val;
EXECUTE stmt_token_val;
DEALLOCATE PREPARE stmt_token_val;

-- 3. Ensure t_access_approval_rate_limit table exists (for clean installs or databases missing V040).
CREATE TABLE IF NOT EXISTS `t_access_approval_rate_limit` (
  `limit_key` CHAR(64) NOT NULL COMMENT 'SHA-256 composite key; never contains raw account or credential',
  `limit_scope` VARCHAR(40) NOT NULL COMMENT 'ONSITE_AUTHORIZE, QR_CREATE, QR_CONFIRM, CREDENTIAL_FAILURE',
  `window_started_at` DATETIME(3) NOT NULL,
  `attempts` INT NOT NULL DEFAULT 0,
  `blocked_until` DATETIME(3) DEFAULT NULL,
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`limit_key`),
  KEY `idx_approval_rate_limit_cleanup` (`updated_at`),
  KEY `idx_approval_rate_limit_blocked` (`blocked_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='审批接口与凭据失败跨实例限流状态';

-- 4. Replay additive exact permissions and role backfills.
INSERT IGNORE INTO `t_permission`
(`permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
('order:operate:refund:approve', '退款审批', '订单', '审批退款/退菜授权，不包含退款执行权', 45),
('order:operate:changePrice:approve', '改价审批', '订单', '审批改价/赠送授权，不包含改价执行权', 46),
('order:operate:discount:approve', '折扣审批', '订单', '审批折扣授权，不包含折扣执行权', 47);

INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT DISTINCT legacy.role_id, exact_permission.id
FROM `t_role_permission` legacy
JOIN `t_permission` legacy_permission ON legacy_permission.id = legacy.permission_id
JOIN `t_permission` exact_permission ON exact_permission.permission_code IN (
  'order:operate:refund:approve',
  'order:operate:changePrice:approve',
  'order:operate:discount:approve'
)
WHERE legacy_permission.permission_code IN ('access:approve', 'refund:approve', 'admin:manage');

INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT role_row.id, permission_row.id
FROM `t_role` role_row
JOIN `t_permission` permission_row ON permission_row.permission_code IN (
  'order:operate:refund:approve',
  'order:operate:changePrice:approve',
  'order:operate:discount:approve'
)
WHERE role_row.role_code IN ('super_admin', 'owner', 'admin');
