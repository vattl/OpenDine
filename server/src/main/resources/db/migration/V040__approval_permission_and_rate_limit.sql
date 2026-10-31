-- WI-061: action-level approval permissions and database-authoritative throttling.

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

INSERT IGNORE INTO `t_permission`
(`permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
('order:operate:refund:approve', '退款审批', '订单', '审批退款/退菜授权，不包含退款执行权', 45),
('order:operate:changePrice:approve', '改价审批', '订单', '审批改价/赠送授权，不包含改价执行权', 46),
('order:operate:discount:approve', '折扣审批', '订单', '审批折扣授权，不包含折扣执行权', 47);

-- Only established approver/administrator roles are backfilled. Action-only roles such as
-- cashier/order operator are deliberately excluded to preserve separation of duties.
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

-- Ensure protected administrator roles retain explicit visibility in role editors.
INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT role_row.id, permission_row.id
FROM `t_role` role_row
JOIN `t_permission` permission_row ON permission_row.permission_code IN (
  'order:operate:refund:approve',
  'order:operate:changePrice:approve',
  'order:operate:discount:approve'
)
WHERE role_row.role_code IN ('super_admin', 'owner', 'admin');
