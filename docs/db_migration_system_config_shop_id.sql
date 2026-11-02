-- t_system_config 增加门店维度：shop_id=0 为全门店默认，>0 为指定门店

-- 可重复执行（已存在 shop_id 或新唯一索引时跳过对应步骤）



SET @has_shop_id := (

    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS

    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_system_config' AND COLUMN_NAME = 'shop_id'

);



SET @ddl := IF(@has_shop_id = 0,

    'ALTER TABLE `t_system_config` ADD COLUMN `shop_id` INT NOT NULL DEFAULT 0 COMMENT ''0=全门店默认，>0=t_shop.id'' AFTER `id`',

    'SELECT 1');

PREPARE stmt FROM @ddl;

EXECUTE stmt;

DEALLOCATE PREPARE stmt;



SET @has_old_uk := (

    SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS

    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_system_config' AND INDEX_NAME = 'uk_config_key'

);



SET @ddl := IF(@has_old_uk > 0,

    'ALTER TABLE `t_system_config` DROP INDEX `uk_config_key`',

    'SELECT 1');

PREPARE stmt FROM @ddl;

EXECUTE stmt;

DEALLOCATE PREPARE stmt;



SET @has_new_uk := (

    SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS

    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_system_config' AND INDEX_NAME = 'uk_shop_config_key'

);



SET @ddl := IF(@has_new_uk = 0,

    'ALTER TABLE `t_system_config` ADD UNIQUE INDEX `uk_shop_config_key` (`shop_id` ASC, `config_key` ASC) USING BTREE',

    'SELECT 1');

PREPARE stmt FROM @ddl;

EXECUTE stmt;

DEALLOCATE PREPARE stmt;



UPDATE `t_system_config`

SET `remark` = '接单后自动发真省钱配送（zsq.auto_api.enabled，1/true=开启）'

WHERE `config_key` = 'zsq.auto_api.enabled';



UPDATE `t_system_config`

SET `remark` = '外卖真省钱配送状态定时同步（zsq.takeout_sync.enabled）'

WHERE `config_key` = 'zsq.takeout_sync.enabled';



INSERT INTO `t_system_config` (`shop_id`, `config_key`, `config_value`, `remark`) VALUES

    (0, 'zsq.auto_api.enabled', 'false', '接单后自动发真省钱配送（全门店默认）'),

    (0, 'zsq.takeout_sync.enabled', 'true', '外卖真省钱配送状态定时同步（全门店默认）')

ON DUPLICATE KEY UPDATE `remark` = VALUES(`remark`);

