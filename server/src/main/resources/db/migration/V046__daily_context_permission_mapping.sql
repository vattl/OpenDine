-- Register permission for aggregated daily close context endpoint
INSERT INTO t_api_permission (method, path_pattern, permission_code, remark) VALUES
('GET', '/admin/daily/context', 'daily:settle|report:view', '日结页面单接口聚合上下文查询')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code), remark = VALUES(remark);
