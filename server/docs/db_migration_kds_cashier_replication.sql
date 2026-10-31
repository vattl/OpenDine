-- LEGACY_TRANSITIONAL: active tests/debug setup still reference this already-deployed schema.
-- Do not use it for new writes or infer that cashier is authoritative.
-- Target architecture: docs/KDS_ARCHITECTURE.md (KDS-CA-1.0).
-- Cashier SQLite -> cloud asynchronous replication.
-- Historical schema description: cashier was the LAN authority and cloud stored its projection.
-- That model is superseded; rows are retained only for migration/backlog adjudication.

CREATE TABLE IF NOT EXISTS `t_kds_replication_event` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `event_id` varchar(128) NOT NULL,
  `shop_id` int NOT NULL,
  `event_type` varchar(40) NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `occurred_at_ms` bigint NOT NULL,
  `operation_id` varchar(128) DEFAULT NULL,
  `local_revision` bigint DEFAULT NULL,
  `payload_json` longtext NOT NULL,
  `publisher_device_code` varchar(64) NOT NULL COMMENT 'Authenticated X-Cashier-Device-Code',
  `request_fingerprint` char(64) NOT NULL COMMENT 'SHA-256 canonical semantic request; excludes idempotency IDs',
  `status` varchar(20) NOT NULL DEFAULT 'received' COMMENT 'received/pending/applied/ignored/failed/dead_letter/replaced/discarded',
  `result_json` longtext DEFAULT NULL,
  `error_code` int DEFAULT NULL,
  `error_message` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `applied_at` datetime DEFAULT NULL,
  `retry_count` int NOT NULL DEFAULT 0,
  `dead_lettered_at` datetime DEFAULT NULL,
  `resolution_action` varchar(20) DEFAULT NULL,
  `resolution_reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `resolved_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_replication_event_id` (`event_id`),
  UNIQUE KEY `uk_kds_replication_operation` (`shop_id`, `operation_id`),
  KEY `idx_kds_replication_pending` (`shop_id`, `aggregate_key`, `status`, `occurred_at_ms`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier-to-cloud durable event inbox';

CREATE TABLE IF NOT EXISTS `t_kds_replication_aggregate` (
  `shop_id` int NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `order_created_applied` tinyint NOT NULL DEFAULT 0,
  `last_occurred_at_ms` bigint DEFAULT NULL,
  `last_order_revision` bigint NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`, `aggregate_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Per-order replication serialization lock';

CREATE TABLE IF NOT EXISTS `t_kds_replication_order_map` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `local_order_no` varchar(100) DEFAULT NULL,
  `cloud_order_id` int NOT NULL,
  `cloud_order_no` varchar(100) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_replication_local_order` (`shop_id`, `local_order_id`),
  UNIQUE KEY `uk_kds_replication_aggregate_map` (`shop_id`, `aggregate_key`),
  UNIQUE KEY `uk_kds_replication_cloud_order` (`cloud_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier local order to cloud order mapping';

CREATE TABLE IF NOT EXISTS `t_kds_replication_detail_map` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `local_detail_id` bigint NOT NULL,
  `cloud_order_id` int NOT NULL,
  `cloud_detail_id` int NOT NULL,
  `last_local_revision` bigint NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_replication_local_detail` (`shop_id`, `local_detail_id`),
  UNIQUE KEY `uk_kds_replication_cloud_detail` (`cloud_detail_id`),
  KEY `idx_kds_replication_detail_order` (`shop_id`, `local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier local detail to cloud detail mapping';

CREATE TABLE IF NOT EXISTS `t_kds_replication_line_state` (
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `local_detail_id` bigint NOT NULL,
  `cloud_order_id` int NOT NULL,
  `cloud_detail_id` int NOT NULL,
  `workflow_queue` varchar(40) DEFAULT NULL,
  `prep_remaining` int DEFAULT NULL,
  `cook_remaining` int DEFAULT NULL,
  `ready_remaining` int DEFAULT NULL,
  `remaining_quantity` int DEFAULT NULL,
  `local_revision` bigint NOT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`, `local_detail_id`),
  KEY `idx_kds_replication_line_order` (`shop_id`, `local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Latest cashier-authoritative KDS line projection';

CREATE TABLE IF NOT EXISTS `t_kds_replication_order_state` (
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `order_revision` bigint NOT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Latest cashier-authoritative order snapshot';

CREATE TABLE IF NOT EXISTS `t_kds_replication_inventory_state` (
  `shop_id` int NOT NULL,
  `dish_id` int NOT NULL,
  `availability_revision` bigint NOT NULL,
  `stock` int DEFAULT NULL,
  `sold_out` tinyint DEFAULT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`dish_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Latest cashier-authoritative dish availability';

CREATE TABLE IF NOT EXISTS `t_kds_replication_dead_letter_audit` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `event_id` varchar(128) NOT NULL,
  `action` varchar(20) NOT NULL COMMENT 'retry/replace/discard',
  `reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `operator_admin_id` int DEFAULT NULL,
  `operator_subject` varchar(128) NOT NULL,
  `trace_id` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_dead_letter_audit` (`shop_id`,`event_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditable dead-letter operator actions';

CREATE TABLE IF NOT EXISTS `t_kds_authority_config_version` (
  `shop_id` int NOT NULL,
  `version` bigint NOT NULL DEFAULT 1,
  `cashier_device_code` varchar(64) DEFAULT NULL COMMENT 'Cashier authority identity; not a t_kds_device display device',
  `snapshot_hash` char(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier-authoritative KDS configuration generation';

INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`)
SELECT '*', '/admin/kds/replication/events', 'cashier:operate'
WHERE NOT EXISTS (
  SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/replication/events'
);

INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`)
SELECT '*', '/admin/kds/replication/events/batch', 'cashier:operate'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/replication/events/batch');
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`)
SELECT '*', '/admin/kds/replication/dead-letters', 'kds:config'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/replication/dead-letters');
UPDATE `t_api_permission` SET `permission_code`='kds:config'
WHERE `path_pattern`='/admin/kds/replication/dead-letters';
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`)
SELECT '*', '/admin/kds/authority/config-snapshot', 'cashier:operate'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/authority/config-snapshot');
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`)
SELECT '*', '/admin/kds/authority/device', 'kds:config'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/authority/device');
