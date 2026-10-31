-- V020: POS Access Control v2 权限中心升级
-- 1. 扩展 t_admin (账户状态机、权限失效版本、登录防爆破、店长PIN码)
SET @dbname = DATABASE();

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'account_status') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `account_status` VARCHAR(20) NOT NULL DEFAULT ''ACTIVE'' COMMENT ''账户状态: ACTIVE, DISABLED, LOCKED, RESIGNED'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'permission_version') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `permission_version` BIGINT NOT NULL DEFAULT 1 COMMENT ''权限版本号，角色/范围变更时递增'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'failed_login_count') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `failed_login_count` INT NOT NULL DEFAULT 0 COMMENT ''连续登录失败次数'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'locked_until') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `locked_until` DATETIME DEFAULT NULL COMMENT ''账号锁定截止时间'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'last_login_at') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `last_login_at` DATETIME DEFAULT NULL COMMENT ''最后登录时间'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'last_login_ip') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `last_login_ip` VARCHAR(64) DEFAULT NULL COMMENT ''最后登录IP'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'password_changed_at') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `password_changed_at` DATETIME DEFAULT NULL COMMENT ''密码修改时间'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'force_logout_at') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `force_logout_at` DATETIME DEFAULT NULL COMMENT ''强制下线时间，签发早于此时的JWT失效'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'manager_pin_hash') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `manager_pin_hash` VARCHAR(128) DEFAULT NULL COMMENT ''店长授权PIN码哈希'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'pin_failed_count') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `pin_failed_count` INT NOT NULL DEFAULT 0 COMMENT ''PIN连续失败次数'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_admin' AND COLUMN_NAME = 'pin_locked_until') > 0,
  'SELECT 1',
  'ALTER TABLE `t_admin` ADD COLUMN `pin_locked_until` DATETIME DEFAULT NULL COMMENT ''PIN锁定截止时间'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- 2. 扩展 t_role (角色类型、编辑保护、系统预置标记、优先级)
SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_role' AND COLUMN_NAME = 'role_type') > 0,
  'SELECT 1',
  'ALTER TABLE `t_role` ADD COLUMN `role_type` VARCHAR(20) NOT NULL DEFAULT ''CUSTOM'' COMMENT ''角色类型: SYSTEM, CUSTOM'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_role' AND COLUMN_NAME = 'editable') > 0,
  'SELECT 1',
  'ALTER TABLE `t_role` ADD COLUMN `editable` TINYINT NOT NULL DEFAULT 1 COMMENT ''是否允许编辑 1=允许 0=禁止'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_role' AND COLUMN_NAME = 'system_protected') > 0,
  'SELECT 1',
  'ALTER TABLE `t_role` ADD COLUMN `system_protected` TINYINT NOT NULL DEFAULT 0 COMMENT ''是否系统受保护角色(不可删除) 1=是 0=否'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = 't_role' AND COLUMN_NAME = 'priority') > 0,
  'SELECT 1',
  'ALTER TABLE `t_role` ADD COLUMN `priority` INT NOT NULL DEFAULT 100 COMMENT ''角色优先级(数值越小优先级越高)'''
));
PREPARE stmt FROM @preparedStatement; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 标记系统预置角色
UPDATE `t_role` SET `role_type` = 'SYSTEM', `system_protected` = 1, `priority` = 10
WHERE `role_code` IN ('super_admin', 'owner', 'admin') AND `role_type` = 'CUSTOM';


-- 3. 策略定义表 t_access_policy
CREATE TABLE IF NOT EXISTS `t_access_policy` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `policy_code` VARCHAR(100) NOT NULL COMMENT '策略唯一编码',
  `policy_name` VARCHAR(100) NOT NULL COMMENT '策略名称',
  `permission_code` VARCHAR(100) NOT NULL COMMENT '绑定的功能权限码',
  `policy_type` VARCHAR(50) NOT NULL COMMENT '策略类型: MAX_AMOUNT, MIN_DISCOUNT_RATE, MAX_DISCOUNT_AMOUNT, MAX_DAILY_COUNT, ORDER_STATUS, TIME_WINDOW',
  `effect` VARCHAR(10) NOT NULL DEFAULT 'ALLOW' COMMENT '默认作用: ALLOW/DENY',
  `priority` INT NOT NULL DEFAULT 100 COMMENT '策略优先级，数值越小优先级越高',
  `enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用 1=启用 0=禁用',
  `config_json` TEXT NOT NULL COMMENT '策略配置规则JSON',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_policy_code` (`policy_code`),
  KEY `idx_permission_code` (`permission_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限策略表' ROW_FORMAT=DYNAMIC;


-- 4. 角色与策略绑定表 t_role_policy
CREATE TABLE IF NOT EXISTS `t_role_policy` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `role_id` INT NOT NULL COMMENT '关联角色ID',
  `policy_id` BIGINT NOT NULL COMMENT '关联策略ID',
  `shop_id` INT DEFAULT NULL COMMENT '门店ID (NULL表示全局适用)',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_role_policy_shop` (`role_id`, `policy_id`, `shop_id`),
  KEY `idx_policy_id` (`policy_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色权限策略绑定表' ROW_FORMAT=DYNAMIC;


-- 5. 员工级显式权限覆盖表 t_admin_permission_override
CREATE TABLE IF NOT EXISTS `t_admin_permission_override` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `admin_id` INT NOT NULL COMMENT '管理员ID',
  `permission_code` VARCHAR(100) NOT NULL COMMENT '权限码',
  `effect` VARCHAR(10) NOT NULL COMMENT '覆盖效果: ALLOW/DENY',
  `shop_id` INT DEFAULT NULL COMMENT '指定门店ID (NULL表示全局)',
  `policy_json` TEXT DEFAULT NULL COMMENT '特定覆盖策略JSON (可选)',
  `valid_from` DATETIME DEFAULT NULL COMMENT '生效开始时间',
  `valid_until` DATETIME DEFAULT NULL COMMENT '生效截止时间',
  `source` VARCHAR(30) NOT NULL DEFAULT 'MANUAL' COMMENT '覆盖来源: MANUAL, TEMP_GRANT, SECURITY_BLOCK',
  `reason` VARCHAR(255) DEFAULT NULL COMMENT '覆盖原因',
  `created_by` INT NOT NULL COMMENT '创建者管理员ID',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_admin_perm_shop` (`admin_id`, `permission_code`, `shop_id`),
  KEY `idx_valid_until` (`valid_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='员工级显式权限覆盖表' ROW_FORMAT=DYNAMIC;


-- 6. 权限审批流水与令牌表 t_access_approval
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


-- 7. SoD 职责分离权限冲突规则表 t_access_conflict_rule
CREATE TABLE IF NOT EXISTS `t_access_conflict_rule` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `permission_a` VARCHAR(100) NOT NULL COMMENT '冲突权限码A',
  `permission_b` VARCHAR(100) NOT NULL COMMENT '冲突权限码B',
  `severity` VARCHAR(20) NOT NULL DEFAULT 'HARD' COMMENT '冲突严重级别: HARD(严禁), SOFT(警告)',
  `enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用 1=启用 0=禁用',
  `message` VARCHAR(255) DEFAULT NULL COMMENT '冲突提示文案',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conflict` (`permission_a`, `permission_b`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoD职责分离权限冲突规则表' ROW_FORMAT=DYNAMIC;


-- 8. 初始化内置 SoD 冲突规则
INSERT IGNORE INTO `t_access_conflict_rule` (`permission_a`, `permission_b`, `severity`, `enabled`, `message`) VALUES
('refund:create', 'refund:approve', 'HARD', 1, '退款发起与退款审批存在职责冲突，严禁配置给同一角色'),
('order:item_void', 'order:void_approve', 'HARD', 1, '退菜操作与退菜审批存在职责冲突'),
('inventory:adjust', 'inventory:approve', 'HARD', 1, '库存盘点调整与库存审批存在职责冲突，严禁配置给同一角色'),
('cash_drawer:cash_out', 'cash_drawer:variance_approve', 'HARD', 1, '钱箱现金支出与长短款审批存在职责冲突'),
('reconciliation:manage', 'reconciliation:approve', 'HARD', 1, '财务对账调整与对账审批存在职责冲突');


-- 9. 接口-权限映射记录补充
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`) VALUES
('*', '/admin/access/conflicts/check', 'access:view|access:manage'),
('*', '/admin/access/policies', 'access:view|access:manage'),
('*', '/admin/access/policies/', 'access:manage'),
('*', '/admin/access/policies/assign', 'access:manage'),
('*', '/admin/access/approvals', 'access:view|access:manage'),
('*', '/admin/access/approvals/', 'access:view|access:manage'),
('*', '/cashier/access/authorize', 'cashier:operate')
ON DUPLICATE KEY UPDATE `permission_code` = VALUES(`permission_code`);


