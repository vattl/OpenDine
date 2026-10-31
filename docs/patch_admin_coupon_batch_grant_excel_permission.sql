INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('POST', '/admin/coupon/user-coupon/batch-grant-excel', 'coupon:manage')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code);
