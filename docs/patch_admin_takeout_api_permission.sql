-- 已有库补充：外卖运营端接口权限（与 docs/init_api_permission.sql 一致）

INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/takeout/config', 'order:view'),
('POST', '/admin/takeout/config/save', 'order:operate'),
('POST', '/admin/takeout/delivery/list', 'order:view'),
('GET', '/admin/takeout/delivery/detail', 'order:view'),
('POST', '/admin/takeout/delivery/status', 'order:operate');
