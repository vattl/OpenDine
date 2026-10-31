CREATE TABLE IF NOT EXISTS t_kds_device_pairing_ticket (
  id BIGINT NOT NULL AUTO_INCREMENT,
  shop_id INT NOT NULL,
  device_code VARCHAR(64) NOT NULL,
  code_hash CHAR(64) NOT NULL,
  expires_at DATETIME NOT NULL,
  consumed_at DATETIME NULL,
  created_by VARCHAR(64) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_kds_pairing_code_hash (code_hash),
  KEY idx_kds_pairing_device_status (shop_id, device_code, consumed_at, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
