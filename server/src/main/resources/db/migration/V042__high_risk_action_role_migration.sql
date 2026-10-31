-- WI-063: migrate high-risk order actions from broad cashier access to exact execute/approve grants.

INSERT IGNORE INTO `t_permission`
(`permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
('order:operate:refund', '退款执行', '订单', '执行退款或退菜；收银入口权限不包含此能力', 40),
('order:operate:changePrice', '改价执行', '订单', '执行改价或赠送；收银入口权限不包含此能力', 41),
('order:operate:discount', '优惠执行', '订单', '执行订单优惠；收银入口权限不包含此能力', 42),
('order:operate:reopen', '反结账执行', '订单', '执行反结账；收银入口权限不包含此能力', 43),
('order:operate:refund:approve', '退款审批', '订单', '审批退款/退菜，不包含执行权', 45),
('order:operate:changePrice:approve', '改价审批', '订单', '审批改价/赠送，不包含执行权', 46),
('order:operate:discount:approve', '优惠审批', '订单', '审批优惠，不包含执行权', 47),
('order:operate:reopen:approve', '反结账审批', '订单', '审批反结账，不包含执行权', 48);

-- The built-in cashier role keeps cashier:operate as the initiation permission only.
-- Do not touch custom roles: their explicit exact grants remain administrator-controlled.
DELETE role_permission
FROM `t_role_permission` role_permission
JOIN `t_role` role_row ON role_row.id = role_permission.role_id
JOIN `t_permission` permission_row ON permission_row.id = role_permission.permission_id
WHERE role_row.role_code = 'cashier'
  AND permission_row.permission_code IN (
    'order:operate:refund',
    'order:operate:changePrice',
    'order:operate:discount',
    'order:operate:reopen',
    'order:operate:refund:approve',
    'order:operate:changePrice:approve',
    'order:operate:discount:approve',
    'order:operate:reopen:approve'
  );

-- Known management roles receive explicit action and approval grants. Super administrators
-- still use the controlled bypass, but explicit rows keep role editors and audits complete.
INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT role_row.id, permission_row.id
FROM `t_role` role_row
JOIN `t_permission` permission_row ON permission_row.permission_code IN (
  'order:operate:refund',
  'order:operate:changePrice',
  'order:operate:discount',
  'order:operate:reopen',
  'order:operate:refund:approve',
  'order:operate:changePrice:approve',
  'order:operate:discount:approve',
  'order:operate:reopen:approve'
)
WHERE role_row.role_code IN (
  'super_admin', 'owner', 'admin', 'boss', 'store_manager', 'shop_manager', 'shop_admin'
);
