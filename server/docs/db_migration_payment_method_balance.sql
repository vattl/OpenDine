-- 在「支付方式」主数据表中登记「余额支付」，与 t_order.payment_method 落库值「余额支付」及 code=balance 对齐（小程序 /order/payByBalance）。
-- 依赖：t_payment_method 已存在；若已执行连锁迁移，应含 shop_id 列（见 db_migration_material_payment_log_shop_id.sql）。

INSERT IGNORE INTO `t_payment_method` (`shop_id`, `code`, `name`, `sort_order`, `enabled`)
VALUES (NULL, 'balance', '余额支付', 40, 1);

-- 若库表尚无 shop_id 列，可改用：
-- INSERT IGNORE INTO `t_payment_method` (`code`, `name`, `sort_order`, `enabled`) VALUES ('balance', '余额支付', 40, 1);
