-- LEGACY_TRANSITIONAL: retained because debug setup and compatibility paths still consume it.
-- New design must use cloud-authoritative V2 events; this file cannot define architecture.
-- Target architecture: docs/KDS_ARCHITECTURE.md (KDS-CA-1.0).
-- 多渠道订单可靠进入收银本地 KDS：事务投影、持久事件游标、主收银租约。
-- MySQL 8.0；可重复执行。上线顺序：先执行本文件，再部署后端和收银端。

CREATE TABLE IF NOT EXISTS `t_kds_order_projection` (
  `order_id` int NOT NULL,
  `shop_id` int NOT NULL,
  `projection_version` bigint NOT NULL,
  `state` varchar(16) NOT NULL,
  `source_channel` varchar(24) NOT NULL,
  `payload_json` longtext NOT NULL,
  `payload_hash` char(64) NOT NULL,
  `last_event_cursor` bigint NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_id`),
  KEY `idx_kds_projection_shop_state_order` (`shop_id`,`state`,`order_id`),
  KEY `idx_kds_projection_shop_cursor` (`shop_id`,`last_event_cursor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='云端订单厨房完整投影';

CREATE TABLE IF NOT EXISTS `t_kds_delivery_event` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '全局持久游标；门店内递增但不保证连续',
  `event_id` char(36) NOT NULL,
  `shop_id` int NOT NULL,
  `order_id` int NOT NULL,
  `projection_version` bigint NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `origin_channel` varchar(24) NOT NULL,
  `origin_device_code` varchar(64) NULL,
  `changed_detail_ids_json` text NULL,
  `payload_json` longtext NOT NULL COMMENT '完整订单厨房投影，消费者无需拼 patch',
  `occurred_at_ms` bigint NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_delivery_event_id` (`event_id`),
  UNIQUE KEY `uk_kds_delivery_order_version` (`order_id`,`projection_version`),
  KEY `idx_kds_delivery_shop_cursor` (`shop_id`,`id`),
  KEY `idx_kds_delivery_shop_created` (`shop_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收银本地 KDS 可靠投递事件日志';

CREATE TABLE IF NOT EXISTS `t_kds_delivery_consumer` (
  `shop_id` int NOT NULL,
  `device_code` varchar(64) NULL,
  `authority_epoch` bigint NOT NULL DEFAULT 0,
  `lease_token_hash` char(64) NULL,
  `lease_until` datetime NULL,
  `ack_cursor` bigint NOT NULL DEFAULT 0,
  `last_delivered_cursor` bigint NOT NULL DEFAULT 0,
  `bootstrap_base_cursor` bigint NOT NULL DEFAULT 0,
  `bootstrap_required` tinyint(1) NOT NULL DEFAULT 1,
  `client_version` varchar(64) NULL,
  `last_seen_at` datetime NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`),
  KEY `idx_kds_delivery_lease_until` (`lease_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='每门店唯一收银 KDS 消费者租约与 ACK';
