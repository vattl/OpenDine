-- 数据分析模块接口权限（与 ApiPermissionMapping.java 一致；按需执行）
INSERT IGNORE INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`) VALUES
('GET', '/admin/analytics/business', 'statistics:view'),
('GET', '/admin/analytics/business/trend', 'statistics:view'),
('GET', '/admin/analytics/dishes', 'statistics:view'),
('GET', '/admin/analytics/customers', 'statistics:view'),
('GET', '/admin/analytics/members', 'statistics:view'),
('GET', '/admin/analytics/marketing', 'statistics:view');
