ALTER TABLE t_payment_merchant_config
    ADD COLUMN api_v2_key_enc TEXT NULL AFTER api_v3_key_enc,
    ADD COLUMN client_cert_p12_ref VARCHAR(512) NULL AFTER private_key_ref;

CREATE TABLE IF NOT EXISTS t_wechat_micropay_attempt (
    id BIGINT NOT NULL AUTO_INCREMENT,
    shop_id INT NOT NULL,
    order_id INT NOT NULL,
    order_no VARCHAR(64) NOT NULL,
    out_trade_no VARCHAR(32) NOT NULL,
    merchant_id VARCHAR(32) NOT NULL DEFAULT '1',
    amount_fen INT NOT NULL,
    status VARCHAR(24) NOT NULL,
    trade_state VARCHAR(32) NULL,
    result_code VARCHAR(32) NULL,
    err_code VARCHAR(64) NULL,
    transaction_id VARCHAR(64) NULL,
    active_key VARCHAR(160) NULL,
    terminal_id VARCHAR(64) NULL,
    client_ip VARCHAR(45) NULL,
    success_time DATETIME NULL,
    last_queried_at DATETIME NULL,
    reversed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_wx_micropay_out_trade_no (out_trade_no),
    UNIQUE KEY uk_wx_micropay_active_key (active_key),
    KEY idx_wx_micropay_shop_order (shop_id, order_no, id),
    KEY idx_wx_micropay_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信付款码支付尝试（不保存付款码）';
