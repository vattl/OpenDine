-- 已有库补充：夜间九折规则接口权限（与 ApiPermissionMapping、openapi x-permission 一致）
INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/config/wechat-prepay-ninefold', 'order:config'),
('PUT', '/admin/config/wechat-prepay-ninefold', 'order:config');
