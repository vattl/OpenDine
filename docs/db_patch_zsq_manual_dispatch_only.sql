-- 关闭「接单后自动发真省钱配送」；仅保留运营手动发单（POST /admin/takeout/delivery/zsq/dispatch）
UPDATE `t_system_config`
SET `config_value` = '0',
    `remark` = '已废弃：仅手动发配送（/admin/takeout/delivery/zsq/dispatch）'
WHERE `config_key` = 'zsq.auto_api.enabled';
