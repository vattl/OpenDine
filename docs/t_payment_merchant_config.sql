-- Sanitized schema reference. Runtime migrations under src/main/resources/db/migration are authoritative.
-- Never commit real app IDs, merchant IDs, API keys, certificate serials or private-key paths here.

CREATE TABLE IF NOT EXISTS `t_payment_merchant_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL DEFAULT 0 COMMENT '0=总部模板，>0=门店',
  `channel` varchar(16) NOT NULL COMMENT 'wechat|alipay',
  `merchant_key` varchar(64) NOT NULL COMMENT '商户实例键',
  `enabled` tinyint NOT NULL DEFAULT 1,
  `status` varchar(16) NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE|RETIRED',
  `credential_version` int NOT NULL DEFAULT 1,
  `app_id` varchar(64) NULL,
  `mch_id` varchar(32) NULL,
  `notify_url` varchar(512) NULL,
  `refund_notify_url` varchar(512) NULL,
  `api_v3_key_enc` text NULL COMMENT 'enc: 密文；生产禁止 plain:',
  `api_v2_key_enc` text NULL COMMENT 'enc: 密文；生产禁止 plain:',
  `serial_no` varchar(128) NULL,
  `platform_pub_key_id` varchar(128) NULL,
  `platform_pub_key_ref` varchar(512) NULL,
  `private_key_ref` varchar(512) NULL,
  `client_cert_p12_ref` varchar(512) NULL,
  `alipay_app_cert_ref` varchar(512) NULL,
  `alipay_public_cert_ref` varchar(512) NULL,
  `alipay_root_cert_ref` varchar(512) NULL,
  `routing_rule_json` json NULL,
  `sort_order` int NOT NULL DEFAULT 0,
  `remark` varchar(255) NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop_channel_key` (`shop_id`, `channel`, `merchant_key`),
  KEY `idx_shop_channel` (`shop_id`, `channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付商户配置（按门店隔离）';

-- 示例只展示非敏感结构；凭据必须通过受控管理接口写入并由主密钥加密。
-- INSERT INTO t_payment_merchant_config
--   (shop_id, channel, merchant_key, enabled, status, credential_version, remark)
-- VALUES (1, 'wechat', 'default', 0, 'ACTIVE', 1, '配置凭据后再启用');
