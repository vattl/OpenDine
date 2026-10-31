-- LEGACY_TRANSITIONAL: retained for installations/tests that still depend on replication schema.
-- It is not the target authority model. New work follows docs/KDS_ARCHITECTURE.md (KDS-CA-1.0).
-- Additive upgrade for installations that already applied db_migration_kds_cashier_replication.sql.
-- Safe to rerun: columns are added only when absent; no table/column is dropped.

DROP PROCEDURE IF EXISTS `p_kds_add_column_if_missing`;
DELIMITER $$
CREATE PROCEDURE `p_kds_add_column_if_missing`(
  IN p_table varchar(64), IN p_column varchar(64), IN p_definition varchar(1000)
)
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=p_table AND COLUMN_NAME=p_column
  ) THEN
    SET @kds_ddl = CONCAT('ALTER TABLE `', p_table, '` ADD COLUMN `', p_column, '` ', p_definition);
    PREPARE kds_stmt FROM @kds_ddl;
    EXECUTE kds_stmt;
    DEALLOCATE PREPARE kds_stmt;
  END IF;
END$$
DELIMITER ;

CALL `p_kds_add_column_if_missing`('t_kds_replication_event','retry_count','int NOT NULL DEFAULT 0');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','dead_lettered_at','datetime DEFAULT NULL');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','resolution_action','varchar(20) DEFAULT NULL');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','resolution_reason','varchar(500) DEFAULT NULL');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','replacement_event_id','varchar(128) DEFAULT NULL');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','resolved_at','datetime DEFAULT NULL');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','request_fingerprint','char(64) DEFAULT NULL COMMENT ''SHA-256 canonical semantic request; excludes idempotency IDs''');
CALL `p_kds_add_column_if_missing`('t_kds_replication_event','publisher_device_code','varchar(64) DEFAULT NULL COMMENT ''Authenticated X-Cashier-Device-Code''');
CALL `p_kds_add_column_if_missing`('t_kds_replication_aggregate','last_order_revision','bigint NOT NULL DEFAULT 0');

CREATE TABLE IF NOT EXISTS `t_kds_replication_order_state` (
  `shop_id` int NOT NULL, `local_order_id` bigint NOT NULL, `order_revision` bigint NOT NULL,
  `payload_json` longtext NOT NULL, `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `t_kds_replication_inventory_state` (
  `shop_id` int NOT NULL, `dish_id` int NOT NULL, `availability_revision` bigint NOT NULL,
  `stock` int DEFAULT NULL, `sold_out` tinyint DEFAULT NULL, `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`dish_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `t_kds_replication_dead_letter_audit` (
  `id` bigint NOT NULL AUTO_INCREMENT, `shop_id` int NOT NULL, `event_id` varchar(128) NOT NULL,
  `action` varchar(20) NOT NULL, `reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL, `operator_admin_id` int DEFAULT NULL,
  `operator_subject` varchar(128) NOT NULL, `trace_id` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_kds_dead_letter_audit` (`shop_id`,`event_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `t_kds_authority_config_version` (
  `shop_id` int NOT NULL, `version` bigint NOT NULL DEFAULT 1,
  `cashier_device_code` varchar(64) DEFAULT NULL, `snapshot_hash` char(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CALL `p_kds_add_column_if_missing`('t_kds_authority_config_version','cashier_device_code','varchar(64) DEFAULT NULL COMMENT ''Cashier authority identity; not a KDS display device''');
CALL `p_kds_add_column_if_missing`('t_kds_replication_dead_letter_audit','operator_admin_id','int DEFAULT NULL');
CALL `p_kds_add_column_if_missing`('t_kds_replication_dead_letter_audit','operator_subject','varchar(128) NOT NULL DEFAULT ''unknown''');
CALL `p_kds_add_column_if_missing`('t_kds_replication_dead_letter_audit','trace_id','varchar(128) DEFAULT NULL');

DROP PROCEDURE IF EXISTS `p_kds_add_column_if_missing`;

INSERT INTO `t_api_permission` (`method`,`path_pattern`,`permission_code`)
SELECT '*','/admin/kds/replication/events/batch','cashier:operate'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/replication/events/batch');
INSERT INTO `t_api_permission` (`method`,`path_pattern`,`permission_code`)
SELECT '*','/admin/kds/replication/dead-letters','kds:config'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/replication/dead-letters');
UPDATE `t_api_permission` SET `permission_code`='kds:config'
WHERE `path_pattern`='/admin/kds/replication/dead-letters';
INSERT INTO `t_api_permission` (`method`,`path_pattern`,`permission_code`)
SELECT '*','/admin/kds/authority/config-snapshot','cashier:operate'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/authority/config-snapshot');
INSERT INTO `t_api_permission` (`method`,`path_pattern`,`permission_code`)
SELECT '*','/admin/kds/authority/device','kds:config'
WHERE NOT EXISTS (SELECT 1 FROM `t_api_permission` WHERE `path_pattern`='/admin/kds/authority/device');
