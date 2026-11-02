-- 真省钱开关（t_system_config.shop_id + 键名；须先执行 db_migration_system_config_shop_id.sql）
INSERT INTO `t_system_config` (`shop_id`, `config_key`, `config_value`, `remark`) VALUES
    (0, 'zsq.auto_api.enabled', '0', '接单后自动发真省钱配送（全门店默认）'),
    (0, 'zsq.takeout_sync.enabled', '1', '外卖真省钱配送状态定时同步（全门店默认）')
ON DUPLICATE KEY UPDATE `remark` = VALUES(`remark`);
