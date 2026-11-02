-- Apply explicitly before deploying C009/T01b. Requires MySQL/InnoDB.
-- Preserve this table and pending rows on application rollback.
CREATE TABLE IF NOT EXISTS t_kds_projection_intent (
  id BIGINT NOT NULL AUTO_INCREMENT,
  order_id INT NOT NULL,
  event_type VARCHAR(32) NOT NULL,
  origin_channel VARCHAR(24) NULL,
  origin_device_code VARCHAR(64) NULL,
  changed_detail_ids_json MEDIUMTEXT NULL,
  attempts BIGINT NOT NULL DEFAULT 0,
  next_attempt_ms BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_kds_intent_due (next_attempt_ms,id),
  KEY idx_kds_intent_order (order_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
