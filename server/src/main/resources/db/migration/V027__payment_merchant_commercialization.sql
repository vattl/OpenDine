ALTER TABLE t_payment_merchant_config
    MODIFY COLUMN merchant_key VARCHAR(64) NOT NULL,
    ADD COLUMN status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE' AFTER enabled,
    ADD COLUMN credential_version INT NOT NULL DEFAULT 1 AFTER status;

CREATE TABLE IF NOT EXISTS t_payment_merchant_config_history (
    id BIGINT NOT NULL AUTO_INCREMENT,
    merchant_config_id BIGINT NOT NULL,
    credential_version INT NOT NULL,
    shop_id INT NOT NULL,
    channel VARCHAR(16) NOT NULL,
    merchant_key VARCHAR(64) NOT NULL,
    app_id VARCHAR(64) NULL,
    mch_id VARCHAR(32) NULL,
    notify_url VARCHAR(512) NULL,
    refund_notify_url VARCHAR(512) NULL,
    api_v3_key_enc TEXT NULL,
    api_v2_key_enc TEXT NULL,
    serial_no VARCHAR(128) NULL,
    platform_pub_key_id VARCHAR(128) NULL,
    platform_pub_key_ref VARCHAR(512) NULL,
    private_key_ref VARCHAR(512) NULL,
    client_cert_p12_ref VARCHAR(512) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_payment_merchant_history_version (merchant_config_id, credential_version),
    KEY idx_payment_merchant_history_shop (shop_id, channel, merchant_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付商户历史凭据版本';

CREATE TABLE IF NOT EXISTS t_payment_merchant_policy (
    shop_id INT NOT NULL,
    allow_global_fallback TINYINT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店支付商户解析策略';

ALTER TABLE t_order
    ADD COLUMN merchant_config_id BIGINT NULL AFTER merchantId,
    ADD COLUMN merchant_key VARCHAR(64) NULL AFTER merchant_config_id,
    ADD COLUMN merchant_config_version INT NULL AFTER merchant_key,
    ADD KEY idx_order_merchant_config (merchant_config_id, merchant_config_version);

ALTER TABLE t_wechat_native_payment_attempt
    ADD COLUMN merchant_config_id BIGINT NULL AFTER merchant_id,
    ADD COLUMN merchant_key VARCHAR(64) NULL AFTER merchant_config_id,
    ADD COLUMN merchant_config_version INT NULL AFTER merchant_key;

ALTER TABLE t_wechat_micropay_attempt
    ADD COLUMN merchant_config_id BIGINT NULL AFTER merchant_id,
    ADD COLUMN merchant_key VARCHAR(64) NULL AFTER merchant_config_id,
    ADD COLUMN merchant_config_version INT NULL AFTER merchant_key;
