-- 夜间九折门店配置接口权限
INSERT IGNORE INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`) VALUES
('GET', '/admin/payment/ninefold', 'payment:config:read'),
('PUT', '/admin/payment/ninefold', 'payment:config:write');
