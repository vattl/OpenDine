-- 已有库补充：按手机号更换订单 openid（与 docs/init_api_permission.sql 一致）
-- 执行后如使用内存映射缓存，可调用后台「重载接口权限」或重启服务。

INSERT INTO t_api_permission (method, path_pattern, permission_code) VALUES
('POST', '/admin/order/reassignOpenidByPhone', 'order:operate');
