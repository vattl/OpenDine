-- CA02/CA04: restartable MySQL migration for cloud-authoritative KDS.
-- Apply explicitly before application startup; runtime performs read-only checks.

CREATE TABLE IF NOT EXISTS t_kds_v2_command (
  shop_id INT NOT NULL,
  command_id VARCHAR(128) NOT NULL,
  actor_id VARCHAR(64) NOT NULL,
  actor_type VARCHAR(32) NOT NULL,
  command_type VARCHAR(64) NOT NULL,
  request_fingerprint CHAR(64) NOT NULL,
  request_schema_version VARCHAR(32) NOT NULL,
  status VARCHAR(16) NOT NULL,
  result_json LONGTEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  applied_at DATETIME NULL,
  PRIMARY KEY (shop_id, command_id),
  KEY idx_kds_v2_command_status_time (status, updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_kds_v2_event_cursor (
  shop_id INT NOT NULL,
  event_seq BIGINT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_kds_v2_event (
  shop_id INT NOT NULL,
  event_seq BIGINT NOT NULL,
  event_id VARCHAR(128) NOT NULL,
  command_id VARCHAR(128) NOT NULL DEFAULT 'system',
  schema_version VARCHAR(32) NOT NULL DEFAULT '2.0',
  entity_id VARCHAR(64) NOT NULL DEFAULT '',
  business_revision BIGINT NOT NULL DEFAULT 0,
  event_json LONGTEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (shop_id, event_seq),
  UNIQUE KEY uk_kds_v2_event_id (shop_id, event_id),
  KEY idx_kds_v2_event_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_kds_shop_authority (
  shop_id INT NOT NULL,
  authority_mode VARCHAR(16) NOT NULL DEFAULT 'legacy',
  protocol_version INT NOT NULL DEFAULT 2,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Upgrade existing C010 installations. MySQL DDL auto-commits, therefore
-- every conditional statement must be independently restartable.
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_order' AND column_name='client_order_id')=0, 'ALTER TABLE t_order ADD COLUMN client_order_id VARCHAR(64) NULL COMMENT ''stable client order id''', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_order' AND column_name='revision')=0, 'ALTER TABLE t_order ADD COLUMN revision BIGINT NOT NULL DEFAULT 0 COMMENT ''canonical order revision''', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_order_detail' AND column_name='client_line_id')=0, 'ALTER TABLE t_order_detail ADD COLUMN client_line_id VARCHAR(64) NULL COMMENT ''stable client line id''', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_order' AND column_name='revision')=0, 'ALTER TABLE t_kds_order ADD COLUMN revision BIGINT NOT NULL DEFAULT 0 COMMENT ''canonical kitchen order revision''', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_command' AND column_name='actor_id')=0, 'ALTER TABLE t_kds_v2_command ADD COLUMN actor_id VARCHAR(64) NOT NULL DEFAULT ''MIGRATED'' AFTER command_id', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_command' AND column_name='actor_type')=0, 'ALTER TABLE t_kds_v2_command ADD COLUMN actor_type VARCHAR(32) NOT NULL DEFAULT ''SYSTEM'' AFTER actor_id', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_command' AND column_name='command_type')=0, 'ALTER TABLE t_kds_v2_command ADD COLUMN command_type VARCHAR(64) NOT NULL DEFAULT ''MIGRATED'' AFTER actor_type', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_command' AND column_name='request_schema_version')=0, 'ALTER TABLE t_kds_v2_command ADD COLUMN request_schema_version VARCHAR(32) NOT NULL DEFAULT ''2.0'' AFTER request_fingerprint', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_event' AND column_name='command_id')=0, 'ALTER TABLE t_kds_v2_event ADD COLUMN command_id VARCHAR(128) NOT NULL DEFAULT ''system'' AFTER event_id', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_event' AND column_name='schema_version')=0, 'ALTER TABLE t_kds_v2_event ADD COLUMN schema_version VARCHAR(32) NOT NULL DEFAULT ''2.0'' AFTER command_id', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_event' AND column_name='entity_id')=0, 'ALTER TABLE t_kds_v2_event ADD COLUMN entity_id VARCHAR(64) NOT NULL DEFAULT '''' AFTER schema_version', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_v2_event' AND column_name='business_revision')=0, 'ALTER TABLE t_kds_v2_event ADD COLUMN business_revision BIGINT NOT NULL DEFAULT 0 AFTER entity_id', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_order' AND index_name='uk_order_shop_client_id')=0, 'ALTER TABLE t_order ADD UNIQUE KEY uk_order_shop_client_id (shop_id,client_order_id)', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_order_detail' AND index_name='uk_detail_order_client_line')=0, 'ALTER TABLE t_order_detail ADD UNIQUE KEY uk_detail_order_client_line (mId,client_line_id)', 'SELECT 1');
PREPARE kds_ca_stmt FROM @ddl;
EXECUTE kds_ca_stmt;
DEALLOCATE PREPARE kds_ca_stmt;
