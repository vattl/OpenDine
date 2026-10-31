CREATE TABLE IF NOT EXISTS t_kds_serve_print_job (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  job_key VARCHAR(160) NOT NULL UNIQUE,
  shop_id INT NOT NULL,
  detail_id INT NOT NULL,
  quantity INT NOT NULL,
  status VARCHAR(20) NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  next_attempt_at DATETIME NULL,
  last_error VARCHAR(500) NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  INDEX idx_kds_serve_print_due (status, next_attempt_at)
);
