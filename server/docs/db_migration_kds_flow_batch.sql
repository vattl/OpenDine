-- 美团 KDS 对齐：流转批次（原始明细不物理合并，数量按批次 FCFS 核销）
CREATE TABLE IF NOT EXISTS `t_kds_flow_batch` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `ticket_id` bigint NOT NULL COMMENT 't_kds_ticket.id',
  `detail_id` int NOT NULL COMMENT 't_order_detail.id',
  `order_id` int NOT NULL,
  `quantity` int NOT NULL DEFAULT 1 COMMENT '本批次份数',
  `dining_channel` varchar(16) DEFAULT NULL COMMENT 'dine_in/pack/takeout',
  `queue_status` varchar(24) NOT NULL DEFAULT 'pending_prep' COMMENT 'pending_prep/pending_cook/ready_serve/done/void',
  `order_time` datetime DEFAULT NULL COMMENT '下单时间（FCFS）',
  `prep_at` datetime DEFAULT NULL COMMENT '配菜完成时间',
  `cooked_at` datetime DEFAULT NULL COMMENT '制作完成时间',
  `served_at` datetime DEFAULT NULL COMMENT '传菜完成时间',
  `void_reason` varchar(32) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_flow_batch_ticket` (`ticket_id`, `queue_status`),
  KEY `idx_kds_flow_batch_detail` (`shop_id`, `detail_id`, `queue_status`),
  KEY `idx_kds_flow_batch_fifo_prep` (`shop_id`, `queue_status`, `order_time`),
  KEY `idx_kds_flow_batch_fifo_cook` (`shop_id`, `queue_status`, `prep_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 流转批次（分批配菜/划菜/传菜 FCFS）';
