-- 邀请首单余额奖励配置接口权限（已有库可单独执行）
INSERT INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/config/invite-first-order-balance-reward', 'order:config'),
('PUT', '/admin/config/invite-first-order-balance-reward', 'order:config');
