CREATE TABLE IF NOT EXISTS `t_payment_refund_request` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `idempotency_key` varchar(64) NOT NULL,
  `out_refund_no` varchar(64) NOT NULL,
  `requested_fen` int NOT NULL,
  `applied_fen` int NOT NULL DEFAULT 0,
  `status` varchar(24) NOT NULL DEFAULT 'REQUESTED',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_refund_idempotency` (`shop_id`, `idempotency_key`),
  UNIQUE KEY `uk_payment_refund_out_no` (`out_refund_no`),
  KEY `idx_payment_refund_order` (`shop_id`, `order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付退款请求与回调幂等账本';

CREATE TABLE IF NOT EXISTS `t_payment_refund_guard` (
  `shop_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `idempotency_key` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`, `order_no`),
  KEY `idx_payment_refund_guard_key` (`shop_id`, `idempotency_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单级退款处理中互斥锁';
