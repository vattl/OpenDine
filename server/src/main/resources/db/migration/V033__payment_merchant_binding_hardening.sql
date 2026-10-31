-- Multi-store / multi-merchant payment identity hardening.
-- The final unique index intentionally fails closed when historical duplicate order_no values exist.

ALTER TABLE t_payment_refund_request
    ADD COLUMN merchant_config_id BIGINT NULL AFTER requested_fen,
    ADD COLUMN merchant_config_version INT NULL AFTER merchant_config_id,
    ADD COLUMN expected_transaction_id VARCHAR(64) NULL AFTER merchant_config_version,
    ADD COLUMN expected_mch_id VARCHAR(32) NULL AFTER expected_transaction_id,
    ADD KEY idx_payment_refund_merchant_config (merchant_config_id, merchant_config_version);

UPDATE t_payment_refund_request r
JOIN t_order o
  ON o.shop_id = r.shop_id
 AND o.order_no = r.order_no
SET r.merchant_config_id = o.merchant_config_id,
    r.merchant_config_version = o.merchant_config_version,
    r.expected_transaction_id = o.transaction_id
WHERE r.merchant_config_id IS NULL
   OR r.merchant_config_version IS NULL
   OR r.expected_transaction_id IS NULL;

UPDATE t_payment_refund_request r
JOIN t_payment_merchant_config m
  ON m.id = r.merchant_config_id
SET r.expected_mch_id = m.mch_id
WHERE r.expected_mch_id IS NULL;

ALTER TABLE t_payment_merchant_config
    ADD KEY idx_payment_merchant_notify_serial (channel, platform_pub_key_id);

ALTER TABLE t_payment_merchant_config_history
    ADD KEY idx_payment_merchant_history_notify_serial (channel, platform_pub_key_id);

ALTER TABLE t_order
    ADD UNIQUE KEY uk_order_order_no (order_no);
