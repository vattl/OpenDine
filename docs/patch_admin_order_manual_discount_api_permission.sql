-- 运营端手动订单优惠 POST /admin/order/manualDiscount
INSERT INTO t_api_permission (method, path, permission_code) VALUES
('POST', '/admin/order/manualDiscount', 'order:operate')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code);
