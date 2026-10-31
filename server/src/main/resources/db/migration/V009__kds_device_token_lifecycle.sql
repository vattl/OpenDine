-- KDS cloud-issued bearer token lifecycle.
-- Corrective and restartable: V008 is immutable once applied.

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_device' AND column_name='token_hash')=0,
  'ALTER TABLE t_kds_device ADD COLUMN token_hash CHAR(64) NULL AFTER device_token', 'SELECT 1');
PREPARE kds_token_stmt FROM @ddl;
EXECUTE kds_token_stmt;
DEALLOCATE PREPARE kds_token_stmt;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_device' AND column_name='token_expires_at')=0,
  'ALTER TABLE t_kds_device ADD COLUMN token_expires_at DATETIME NULL AFTER token_hash', 'SELECT 1');
PREPARE kds_token_stmt FROM @ddl;
EXECUTE kds_token_stmt;
DEALLOCATE PREPARE kds_token_stmt;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_device' AND column_name='token_revoked_at')=0,
  'ALTER TABLE t_kds_device ADD COLUMN token_revoked_at DATETIME NULL AFTER token_expires_at', 'SELECT 1');
PREPARE kds_token_stmt FROM @ddl;
EXECUTE kds_token_stmt;
DEALLOCATE PREPARE kds_token_stmt;

UPDATE t_kds_device
SET token_hash = SHA2(device_token, 256),
    token_expires_at = COALESCE(token_expires_at, DATE_ADD(NOW(), INTERVAL 30 DAY)),
    token_revoked_at = CASE WHEN enabled = 0 THEN COALESCE(token_revoked_at, NOW()) ELSE token_revoked_at END
WHERE device_token IS NOT NULL AND device_token <> '' AND token_hash IS NULL;

-- A duplicated historical bearer credential is unsafe. Revoke every duplicate and require login.
UPDATE t_kds_device d
JOIN (SELECT token_hash FROM (
  SELECT token_hash FROM t_kds_device WHERE token_hash IS NOT NULL GROUP BY token_hash HAVING COUNT(*) > 1
) duplicate_hashes) duplicates
  ON duplicates.token_hash = d.token_hash
SET d.token_hash = NULL,
    d.token_revoked_at = COALESCE(d.token_revoked_at, NOW());

-- Raw bearer credentials are no longer a cloud database field after the hash backfill.
UPDATE t_kds_device SET device_token = NULL WHERE device_token IS NOT NULL;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_kds_device' AND index_name='uk_kds_device_token_hash')=0,
  'ALTER TABLE t_kds_device ADD UNIQUE KEY uk_kds_device_token_hash (token_hash)', 'SELECT 1');
PREPARE kds_token_stmt FROM @ddl;
EXECUTE kds_token_stmt;
DEALLOCATE PREPARE kds_token_stmt;

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_kds_device' AND index_name='idx_kds_device_token_status')=0,
  'ALTER TABLE t_kds_device ADD KEY idx_kds_device_token_status (enabled, token_expires_at, token_revoked_at)', 'SELECT 1');
PREPARE kds_token_stmt FROM @ddl;
EXECUTE kds_token_stmt;
DEALLOCATE PREPARE kds_token_stmt;
