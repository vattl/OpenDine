-- 运营端外卖配送追踪 GET /admin/takeout/delivery/tracking
INSERT INTO t_api_permission (method, path, permission_code) VALUES
('GET', '/admin/takeout/delivery/tracking', 'order:view')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code);
