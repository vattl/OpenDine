-- 微信支付平台公钥 PEM 引用（classpath: 或内联 PEM），供下单与回调验签从 DB 加载
-- 可重复执行：列已存在时跳过 ALTER

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

-- 种子：与 application.yml pubSerial-path 对齐（可按环境修改）
UPDATE `t_payment_merchant_config`
SET `platform_pub_key_ref` = 'classpath:pub_key.pem'
WHERE `channel` = 'wechat' AND `merchant_key` = 'default' AND (`platform_pub_key_ref` IS NULL OR `platform_pub_key_ref` = '');

UPDATE `t_payment_merchant_config`
SET `platform_pub_key_ref` = 'classpath:pub_key2.pem'
WHERE `channel` = 'wechat' AND `merchant_key` = 'small_amount' AND (`platform_pub_key_ref` IS NULL OR `platform_pub_key_ref` = '');
