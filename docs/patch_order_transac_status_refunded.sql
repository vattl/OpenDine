



ALTER TABLE `t_order`
  ADD COLUMN `refund_amount` decimal(10, 2) NULL DEFAULT NULL COMMENT '累计成功退款金额（元），由微信 /order/refund/notify 退款成功(SUCCESS)回调累加' AFTER `service_fee`;
