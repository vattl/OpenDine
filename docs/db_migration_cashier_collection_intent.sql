CREATE TABLE IF NOT EXISTS `t_cashier_collection_intent` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `session_id` varchar(64) NOT NULL,
  `channel` varchar(16) NOT NULL,
  `amount_fen` int NOT NULL,
  `status` varchar(24) NOT NULL DEFAULT 'PENDING',
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_cashier_collection_order_channel` (`shop_id`, `order_no`, `channel`),
  KEY `idx_cashier_collection_session` (`session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收银人工扫码出码占用';

-- Earlier draft installations are migrated automatically by
-- CashierCollectionIntentService.ensureSchema(). Do not run a blind DROP INDEX
-- here because fresh installations already use the channel-aware unique key.
