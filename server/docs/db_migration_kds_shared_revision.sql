-- C010/T006: durable revisions shared by cashier LAN replication and cloud KDS.
-- Apply before deploying code that requires t_kds_ticket.order_revision.

DROP PROCEDURE IF EXISTS p_kds_add_column_if_missing;
DELIMITER $$
CREATE PROCEDURE p_kds_add_column_if_missing(
  IN p_table VARCHAR(64),
  IN p_column VARCHAR(64),
  IN p_definition TEXT
)
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = p_table
      AND COLUMN_NAME = p_column
  ) THEN
    SET @kds_revision_ddl = CONCAT(
      'ALTER TABLE `', p_table, '` ADD COLUMN `', p_column, '` ', p_definition
    );
    PREPARE kds_revision_stmt FROM @kds_revision_ddl;
    EXECUTE kds_revision_stmt;
    DEALLOCATE PREPARE kds_revision_stmt;
  END IF;
END$$
DELIMITER ;

CALL p_kds_add_column_if_missing(
  't_kds_ticket',
  'row_version',
  'BIGINT NOT NULL DEFAULT 1 COMMENT ''KDS V2 detail revision'''
);
CALL p_kds_add_column_if_missing(
  't_kds_ticket',
  'order_revision',
  'BIGINT NOT NULL DEFAULT 1 COMMENT ''KDS V2 order revision'' AFTER `row_version`'
);

DROP PROCEDURE IF EXISTS p_kds_add_column_if_missing;

ALTER TABLE t_kds_ticket
  MODIFY COLUMN row_version BIGINT NOT NULL DEFAULT 1 COMMENT 'KDS V2 detail revision',
  MODIFY COLUMN order_revision BIGINT NOT NULL DEFAULT 1 COMMENT 'KDS V2 order revision';

UPDATE t_kds_ticket SET row_version = 1
WHERE row_version IS NULL OR row_version < 1;
UPDATE t_kds_ticket SET order_revision = 1
WHERE order_revision IS NULL OR order_revision < 1;

-- Backfill existing cashier-originated tickets without moving revisions back.
UPDATE t_kds_ticket t
JOIN t_kds_replication_detail_map dm
  ON dm.shop_id = t.shop_id AND dm.cloud_detail_id = t.detail_id
SET t.row_version = GREATEST(t.row_version, dm.last_local_revision);

UPDATE t_kds_ticket t
JOIN t_kds_replication_order_map om
  ON om.shop_id = t.shop_id AND om.cloud_order_id = t.order_id
JOIN t_kds_replication_order_state os
  ON os.shop_id = om.shop_id AND os.local_order_id = om.local_order_id
SET t.order_revision = GREATEST(t.order_revision, os.order_revision);
