-- Apply before deploying bounded automatic-fulfillment retries.
-- Additive only; existing orders remain unchanged and the index can be dropped independently on rollback.
DELIMITER $$
CREATE PROCEDURE p_add_order_fulfillment_retry_index()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 't_order'
      AND INDEX_NAME = 'idx_order_fulfillment_retry'
  ) THEN
    CREATE INDEX idx_order_fulfillment_retry
      ON t_order (order_receiving, transac_status, order_time, id);
  END IF;
END$$
DELIMITER ;
CALL p_add_order_fulfillment_retry_index();
DROP PROCEDURE p_add_order_fulfillment_retry_index;
