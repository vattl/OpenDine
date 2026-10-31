-- 线上支付模块：商户配置 + 支付能力开关
-- 执行后请运行应用或调用后台接口刷新内存缓存；商户密钥建议通过运营后台重新保存以启用加密存储

CREATE TABLE IF NOT EXISTS `t_payment_merchant_config` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `shop_id` INT NOT NULL DEFAULT 0 COMMENT '0=全门店默认，>0=t_shop.id',
  `channel` VARCHAR(16) NOT NULL COMMENT 'wechat|alipay',
  `merchant_key` VARCHAR(32) NOT NULL COMMENT '实例键，如 default、small_amount',
  `enabled` TINYINT NOT NULL DEFAULT 1,
  `app_id` VARCHAR(64) NULL DEFAULT NULL,
  `mch_id` VARCHAR(32) NULL DEFAULT NULL COMMENT '微信商户号或支付宝 PID',
  `notify_url` VARCHAR(512) NULL DEFAULT NULL,
  `refund_notify_url` VARCHAR(512) NULL DEFAULT NULL,
  `api_v3_key_enc` VARCHAR(512) NULL DEFAULT NULL COMMENT '微信 APIv3 密钥（加密或 plain: 前缀）',
  `serial_no` VARCHAR(64) NULL DEFAULT NULL,
  `platform_pub_key_id` VARCHAR(128) NULL DEFAULT NULL COMMENT '微信 Wechatpay-Serial 公钥 ID',
  `platform_pub_key_ref` VARCHAR(512) NULL DEFAULT NULL COMMENT '微信官方平台公钥 PEM 或 classpath:/pub_key.pem',
  `private_key_ref` VARCHAR(512) NULL DEFAULT NULL COMMENT '商户私钥 PEM 密文或 classpath:/path',
  `alipay_app_cert_ref` VARCHAR(512) NULL DEFAULT NULL,
  `alipay_public_cert_ref` VARCHAR(512) NULL DEFAULT NULL,
  `alipay_root_cert_ref` VARCHAR(512) NULL DEFAULT NULL,
  `routing_rule_json` JSON NULL COMMENT '商户路由规则',
  `sort_order` INT NOT NULL DEFAULT 0,
  `remark` VARCHAR(255) NULL DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop_channel_key` (`shop_id`, `channel`, `merchant_key`),
  KEY `idx_shop_channel` (`shop_id`, `channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='支付商户配置（连锁按 shop_id 覆盖）';

-- 旧库升级：CREATE IF NOT EXISTS 不会给已有表补列（须在 INSERT 种子数据之前执行）
DROP PROCEDURE IF EXISTS `_patch_payment_platform_pub_key_ref`;
DELIMITER //
CREATE PROCEDURE `_patch_payment_platform_pub_key_ref`()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 't_payment_merchant_config'
          AND COLUMN_NAME = 'platform_pub_key_ref'
    ) THEN
        ALTER TABLE `t_payment_merchant_config`
            ADD COLUMN `platform_pub_key_ref` VARCHAR(512) NULL DEFAULT NULL
                COMMENT '微信官方平台公钥 PEM 或 classpath:/pub_key.pem'
                AFTER `platform_pub_key_id`;
    END IF;
END //
DELIMITER ;
CALL `_patch_payment_platform_pub_key_ref`();
DROP PROCEDURE IF EXISTS `_patch_payment_platform_pub_key_ref`;

CREATE TABLE IF NOT EXISTS `t_payment_capability` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `shop_id` INT NOT NULL DEFAULT 0 COMMENT '0=全门店默认',
  `online_pay_enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '线上支付总开关（微信/支付宝/余额）',
  `wechat_enabled` TINYINT NOT NULL DEFAULT 1,
  `alipay_enabled` TINYINT NOT NULL DEFAULT 0 COMMENT '支付宝官方支付，P3 启用',
  `balance_enabled` TINYINT NOT NULL DEFAULT 1,
  `combined_enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '线上组合支付开关',
  `cashier_pay_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端支付总开关',
  `cashier_wechat_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端微信支付',
  `cashier_alipay_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端支付宝支付',
  `cashier_balance_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端余额支付',
  `cashier_combined_enabled` TINYINT NULL DEFAULT NULL COMMENT '收银端组合支付',
  `mini_program_pay_enabled` TINYINT NULL DEFAULT NULL COMMENT '微信小程序端支付总开关',
  `mini_program_wechat_enabled` TINYINT NULL DEFAULT NULL COMMENT '微信小程序端微信支付',
  `mini_program_balance_enabled` TINYINT NULL DEFAULT NULL COMMENT '微信小程序端余额支付',
  `offline_collect_enabled` TINYINT NOT NULL DEFAULT 1,
  `offline_collect_channels` VARCHAR(32) NOT NULL DEFAULT 'wechat,alipay',
  `disabled_message` VARCHAR(255) NOT NULL DEFAULT '请联系服务员结账',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店支付能力开关';

-- 旧库升级：补组合支付开关
DROP PROCEDURE IF EXISTS `_patch_payment_combined_enabled`;
DELIMITER //
CREATE PROCEDURE `_patch_payment_combined_enabled`()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 't_payment_capability'
          AND COLUMN_NAME = 'combined_enabled'
    ) THEN
        ALTER TABLE `t_payment_capability`
            ADD COLUMN `combined_enabled` TINYINT NOT NULL DEFAULT 1
                COMMENT '线上组合支付开关'
                AFTER `balance_enabled`;
    END IF;
END //
DELIMITER ;
CALL `_patch_payment_combined_enabled`();
DROP PROCEDURE IF EXISTS `_patch_payment_combined_enabled`;

-- 默认能力：线上与各渠道开启（支付宝官方默认关）
INSERT IGNORE INTO `t_payment_capability` (
  `shop_id`, `online_pay_enabled`, `wechat_enabled`, `alipay_enabled`,
  `balance_enabled`, `combined_enabled`, `offline_collect_enabled`, `offline_collect_channels`, `disabled_message`
) VALUES (
  0, 1, 1, 0, 1, 1, 1, 'wechat,alipay', '请联系服务员结账'
);

-- 微信商户空白种子（不提交任何真实凭据；部署后通过受控后台配置并启用）
INSERT IGNORE INTO `t_payment_merchant_config` (
  `shop_id`, `channel`, `merchant_key`, `enabled`, `app_id`, `mch_id`,
  `notify_url`, `refund_notify_url`, `api_v3_key_enc`, `serial_no`, `platform_pub_key_id`, `platform_pub_key_ref`,
  `private_key_ref`, `routing_rule_json`, `sort_order`, `remark`
) VALUES (
  0, 'wechat', 'default', 0,
  NULL, NULL,
  NULL, NULL,
  NULL, NULL,
  NULL,
  NULL,
  NULL,
  NULL, 10, '空白模板：配置凭据后再启用'
),
(
  0, 'wechat', 'small_amount', 0,
  NULL, NULL,
  NULL, NULL,
  NULL, NULL,
  NULL,
  NULL,
  NULL,
  '{"type":"amount_and_dining","enabledFlag":"wxzf","diningTypes":["打包","外卖"],"maxPaidYuan":159,"targetMerchantKey":"small_amount","defaultMerchantKey":"default"}',
  20, '空白模板：配置凭据后再启用'
);
