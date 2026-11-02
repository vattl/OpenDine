-- D012: 取消订单时 t_order 结账状态与接单状态同时置 cancelled。
-- 存量库 t_order.order_receiving 枚举必须包含 'cancelled'，否则取消时 UPDATE 会 Data truncated。
-- 幂等：无论当前枚举是否已含 cancelled，重复执行均安全（仅归一化定义）。
ALTER TABLE `t_order`
  MODIFY COLUMN `order_receiving` enum('mis_order','rec_order','off_order','cancelled') NOT NULL COMMENT '接单状态：mis_order/rec_order/off_order/cancelled';
