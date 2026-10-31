-- 外卖真省钱桥接接口权限（B 端）
INSERT INTO t_api_permission (method, path, permission_code) VALUES
('POST', '/admin/takeout/delivery/zsq/dispatch', 'order:operate'),
('POST', '/admin/takeout/delivery/zsq/redispatch', 'order:operate'),
('POST', '/admin/takeout/delivery/zsq/sync', 'order:operate')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code);
