-- 运营报表：GET /admin/report/recharge/list（与 /admin/report/dashboard 同权统计类）
INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/report/recharge/list', 'statistics:view');
