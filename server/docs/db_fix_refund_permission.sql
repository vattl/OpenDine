-- 修复退款接口权限码：admin:manage -> order:operate:refund
UPDATE t_api_permission SET permission_code = 'order:operate:refund'
WHERE method = 'POST' AND path_pattern = '/admin/order/refund';

UPDATE t_api_permission SET permission_code = 'order:operate:refund'
WHERE method = 'POST' AND path_pattern = '/cashier/order/refund';

UPDATE t_api_permission SET permission_code = 'order:operate:refund'
WHERE method = 'POST' AND path_pattern = '/cashier/order/refundDish';

INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order)
VALUES ('order:operate:refund', '退款', '订单', '微信退款/退菜', 23);