-- V012: archive tables for KDS V2 command ledger and event log retention.
-- Supports cold/hot data tiering, preventing unbounded table growth.

CREATE TABLE IF NOT EXISTS t_kds_v2_command_archive (
  shop_id INT NOT NULL,
  command_id VARCHAR(128) NOT NULL,
  actor_id VARCHAR(64) NOT NULL,
  actor_type VARCHAR(32) NOT NULL,
  command_type VARCHAR(64) NOT NULL,
  request_fingerprint CHAR(64) NOT NULL,
  request_schema_version VARCHAR(32) NOT NULL,
  status VARCHAR(16) NOT NULL,
  result_json LONGTEXT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  applied_at DATETIME NULL,
  archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (shop_id, command_id),
  KEY idx_kds_v2_cmd_arch_status_time (status, updated_at),
  KEY idx_kds_v2_cmd_arch_archived_at (archived_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_kds_v2_event_archive (
  shop_id INT NOT NULL,
  event_seq BIGINT NOT NULL,
  event_id VARCHAR(128) NOT NULL,
  command_id VARCHAR(128) NOT NULL DEFAULT 'system',
  schema_version VARCHAR(32) NOT NULL DEFAULT '2.0',
  entity_id VARCHAR(64) NOT NULL DEFAULT '',
  business_revision BIGINT NOT NULL DEFAULT 0,
  event_json LONGTEXT NOT NULL,
  created_at DATETIME NOT NULL,
  archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (shop_id, event_seq),
  UNIQUE KEY uk_kds_v2_event_arch_id (shop_id, event_id),
  KEY idx_kds_v2_event_arch_created (created_at),
  KEY idx_kds_v2_event_arch_archived_at (archived_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
