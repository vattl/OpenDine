-- WI-060: approval token plaintext removal and authenticated envelope migration.
-- This column was introduced by a historical manual script and may not exist on every database.
SET @ddl = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND table_name = 't_access_approval'
     AND column_name = 'token_value') = 0,
  'ALTER TABLE `t_access_approval` ADD COLUMN `token_value` varchar(512) NULL COMMENT ''二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌'' AFTER `token_hash`',
  'ALTER TABLE `t_access_approval` MODIFY COLUMN `token_value` varchar(512) NULL COMMENT ''二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌'''
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Pre-envelope values have no authenticated prefix and must never be returned after upgrade.
-- Their maximum lifetime was already 120 seconds; expiring them is safer than attempting to migrate secrets.
UPDATE `t_access_approval`
SET `status` = CASE
        WHEN `status` IN ('PENDING', 'APPROVED') THEN 'EXPIRED'
        ELSE `status`
    END,
    `token_value` = NULL
WHERE `token_value` IS NOT NULL
  AND `token_value` <> ''
  AND `token_value` NOT LIKE 'aet:v1:%';
