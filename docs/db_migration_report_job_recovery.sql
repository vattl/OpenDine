-- Apply once explicitly with old application workers stopped before deploying T03.
ALTER TABLE t_report_export_job
  ADD COLUMN run_token VARCHAR(32) NULL,
  ADD COLUMN lease_until DATETIME NULL,
  ADD INDEX idx_report_job_recovery(job_type,status,lease_until,id),
  ADD INDEX idx_report_job_shop_pending(shop_id,status,job_type);
CREATE TABLE IF NOT EXISTS t_report_job_admission (
  id INT NOT NULL PRIMARY KEY
) ENGINE=InnoDB;
INSERT IGNORE INTO t_report_job_admission(id) VALUES(1);
-- Keep columns and jobs on rollback. Never clear PENDING/RUNNING work.
