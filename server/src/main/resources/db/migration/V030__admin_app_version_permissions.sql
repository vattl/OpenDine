-- Version management endpoints are intentionally restricted to super administrators.
-- path_pattern is globally unique, so use '*' for the stored method and update
-- existing rows idempotently when a production database was patched manually.
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('*', '/admin/app/versions', 'admin:super', '版本中心-策略列表'),
('*', '/admin/app/version/save', 'admin:super', '版本中心-发布或修改策略'),
('*', '/admin/app/version/toggle-enabled', 'admin:super', '版本中心-启用停用策略'),
('*', '/admin/app/version/*', 'admin:super', '版本中心-删除策略')
ON DUPLICATE KEY UPDATE
  `method`=VALUES(`method`),
  `permission_code`=VALUES(`permission_code`),
  `remark`=VALUES(`remark`);
