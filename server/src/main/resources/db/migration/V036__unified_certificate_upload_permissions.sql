-- WI-037: Unified payment certificate upload permissions
INSERT INTO t_api_permission (method, path_pattern, permission_code, remark) VALUES
('POST', '/admin/payment/certificate/upload', 'payment:config:write', '统一支付证书凭证上传'),
('POST', '/admin/payment/merchants/{id}/certificate/upload', 'payment:config:write', '商户直绑证书凭证上传')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code), remark = VALUES(remark);
