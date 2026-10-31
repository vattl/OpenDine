-- C007: explicit, restartable MySQL migration. No business startup DDL.
CREATE TABLE IF NOT EXISTS t_payment_refund_request (id BIGINT NOT NULL AUTO_INCREMENT,shop_id INT NOT NULL,order_no VARCHAR(64) NOT NULL,idempotency_key VARCHAR(64) NOT NULL,out_refund_no VARCHAR(64) NOT NULL,requested_fen INT NOT NULL,applied_fen INT NOT NULL DEFAULT 0,status VARCHAR(24) NOT NULL DEFAULT 'REQUESTED',created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY (id),UNIQUE KEY uk_payment_refund_idempotency (shop_id, idempotency_key),UNIQUE KEY uk_payment_refund_out_no (out_refund_no),KEY idx_payment_refund_order (shop_id, order_no)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_payment_refund_guard (shop_id INT NOT NULL,order_no VARCHAR(64) NOT NULL,idempotency_key VARCHAR(64) NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY (shop_id, order_no),KEY idx_payment_refund_guard_key (shop_id, idempotency_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_cashier_collection_intent (id BIGINT NOT NULL AUTO_INCREMENT,shop_id INT NOT NULL,order_no VARCHAR(64) NOT NULL,session_id VARCHAR(64) NOT NULL,channel VARCHAR(16) NOT NULL,amount_fen INT NOT NULL,status VARCHAR(24) NOT NULL DEFAULT 'PENDING',expires_at DATETIME NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY (id),UNIQUE KEY uk_cashier_collection_order_channel (shop_id, order_no, channel),KEY idx_cashier_collection_session (session_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_invite_reward_clawback (id BIGINT NOT NULL AUTO_INCREMENT,invite_record_id BIGINT NOT NULL,inviter_user_id INT NOT NULL,order_no VARCHAR(64) NOT NULL,outstanding_amount DECIMAL(12,2) NOT NULL,status VARCHAR(16) NOT NULL DEFAULT 'PENDING',attempts INT NOT NULL DEFAULT 0,last_error VARCHAR(255) NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY (id),UNIQUE KEY uk_invite_clawback_order (invite_record_id, order_no),KEY idx_invite_clawback_status (status, updated_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_personal_payment_event (id BIGINT NOT NULL AUTO_INCREMENT,event_id VARCHAR(128) NOT NULL,channel VARCHAR(32) NOT NULL,amount_fen BIGINT NOT NULL,amount_yuan DECIMAL(10, 2) NOT NULL,timestamp_raw VARCHAR(64) NULL DEFAULT NULL,raw_text TEXT NULL,matched_shop_id INT NULL DEFAULT NULL,matched_order_no VARCHAR(64) NULL DEFAULT NULL,status VARCHAR(32) NOT NULL DEFAULT 'PROCESSED',remark VARCHAR(255) NULL DEFAULT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY (id),UNIQUE KEY uk_personal_pay_event_id (event_id),KEY idx_personal_pay_created (created_at),KEY idx_personal_pay_matched_order (matched_order_no)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS t_kds_device_workflow (
 device_id BIGINT NOT NULL PRIMARY KEY,
 workflows VARCHAR(64) NOT NULL,
 updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Idempotent index transition; DDL may auto-commit. The CLI records completion only at the end.
SET @has_old = (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_cashier_collection_intent' AND index_name='uk_cashier_collection_order');
SET @has_new = (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_cashier_collection_intent' AND index_name='uk_cashier_collection_order_channel');
SET @ddl = IF(@has_new=0, 'ALTER TABLE t_cashier_collection_intent ADD UNIQUE KEY uk_cashier_collection_order_channel (shop_id,order_no,channel)', 'SELECT 1');
PREPARE audit_stmt FROM @ddl;
EXECUTE audit_stmt;
DEALLOCATE PREPARE audit_stmt;
SET @ddl = IF(@has_old>0, 'ALTER TABLE t_cashier_collection_intent DROP INDEX uk_cashier_collection_order', 'SELECT 1');
PREPARE audit_stmt FROM @ddl;
EXECUTE audit_stmt;
DEALLOCATE PREPARE audit_stmt;
UPDATE t_invite_reward_clawback SET outstanding_amount=0 WHERE status='COMPLETED' AND outstanding_amount<>0;
