-- 套餐管理接口权限（与 ApiPermissionMapping 一致，可重复执行）
INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/combo/getByDishId', 'dish:manage'),
('POST', '/admin/combo/save', 'dish:manage');
