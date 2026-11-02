-- 线上支付模块 B 端接口权限（执行于 db_migration_payment_module.sql 之后）
-- 权限码需在运营 RBAC 中授予具备 order:config 或独立 payment:config 的角色

INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/payment/capabilities', 'payment:config:read'),
('PUT', '/admin/payment/capabilities', 'payment:config:write'),
('GET', '/admin/payment/merchants', 'payment:config:read'),
('GET', '/admin/payment/merchants/', 'payment:config:read'),
('GET', '/admin/payment/merchants/edit-form', 'payment:config:read'),
('POST', '/admin/payment/merchants', 'payment:config:write'),
('PUT', '/admin/payment/merchants/', 'payment:config:write'),
('PUT', '/admin/payment/merchants/save', 'payment:config:write'),
('DELETE', '/admin/payment/merchants/', 'payment:config:write'),
('GET', '/admin/payment/merchant-policy', 'payment:config:read'),
('PUT', '/admin/payment/merchant-policy', 'payment:config:write'),
('POST', '/admin/payment/private-key/upload', 'payment:config:write'),
('GET', '/admin/payment/notify-urls', 'payment:config:read'),
('GET', '/admin/payment/wechat/pay-auth-audit', 'payment:config:read');
