-- 运营看板 GET /admin/report/dashboard 权限（已有库可单独执行）
INSERT INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/report/dashboard', 'statistics:view');
