-- V013: Add KDS store 6-digit PIN code to t_kds_shop_config.
-- Default is '123456' for instant kitchen screen login without pairing codes.

SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t_kds_shop_config' AND column_name='kds_pin')=0,
  'ALTER TABLE t_kds_shop_config ADD COLUMN kds_pin VARCHAR(32) NOT NULL DEFAULT \'123456\' COMMENT \'KDS门店登录PIN码\' AFTER enable_prep_workflow', 'SELECT 1');
PREPARE kds_pin_stmt FROM @ddl;
EXECUTE kds_pin_stmt;
DEALLOCATE PREPARE kds_pin_stmt;
