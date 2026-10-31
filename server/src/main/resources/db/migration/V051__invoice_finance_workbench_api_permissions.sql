-- WI-075 / Hotfix: Register API permissions for invoice finance manual workbench and workflow

-- 1. Ensure fine-grained invoice operate permission exists in dictionary t_permission
INSERT IGNORE INTO `t_permission`
(`permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
('order:invoice:operate', '处理发票申请', '订单', '人工开具与驳回发票申请', 32);

-- 2. Bind invoice operate permission to management roles
INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT role_row.id, permission_row.id
FROM `t_role` role_row
JOIN `t_permission` permission_row ON permission_row.permission_code IN (
  'order:invoice:operate'
)
WHERE role_row.role_code IN (
  'super_admin', 'owner', 'admin', 'boss', 'store_manager', 'shop_manager', 'shop_admin'
);

-- 3. Register endpoint permission mappings into t_api_permission
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('GET', '/admin/order/invoice/list', 'order:view|order:invoice:view', '财务后台开票申请列表查询'),
('*', '/admin/order/invoice/list', 'order:view|order:invoice:view', '财务后台开票申请列表查询'),
('POST', '/admin/order/invoice/reject', 'order:operate|order:invoice:operate', '财务后台开票申请驳回'),
('*', '/admin/order/invoice/reject', 'order:operate|order:invoice:operate', '财务后台开票申请驳回'),
('POST', '/admin/order/invoice/issue', 'order:operate|order:invoice:operate', '财务后台录入发票号确认开票'),
('*', '/admin/order/invoice/issue', 'order:operate|order:invoice:operate', '财务后台录入发票号确认开票')
ON DUPLICATE KEY UPDATE `permission_code` = VALUES(`permission_code`), `remark` = VALUES(`remark`);
