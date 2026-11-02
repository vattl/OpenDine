-- KDS 模块接口权限（执行于 db_migration_kds.sql 之后）
-- 权限码需在运营 RBAC 中授予 kitchen_staff / kitchen_manager 等角色

INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/kds/station/list', 'kds:config'),
('POST', '/admin/kds/station/save', 'kds:config'),
('GET', '/admin/kds/station/delete', 'kds:config'),
('POST', '/admin/kds/station/init-five', 'kds:config'),
('POST', '/admin/kds/station/category/bind', 'kds:config'),
('GET', '/admin/kds/station/category/list', 'kds:config'),
('POST', '/admin/kds/dish-screen/bind', 'kds:config'),
('GET', '/admin/kds/dish-screen/list', 'kds:config'),
('GET', '/admin/kds/config/get', 'kds:config'),
('POST', '/admin/kds/config/save', 'kds:config'),
('GET', '/admin/kds/device/list', 'kds:config'),
('POST', '/admin/kds/device/bind', 'kds:config'),
('POST', '/admin/kds/device/unbind', 'kds:config'),
('POST', '/admin/kds/ticket/print-serve', 'cashier:operate|kds:config')
ON DUPLICATE KEY UPDATE permission_code=VALUES(permission_code);
