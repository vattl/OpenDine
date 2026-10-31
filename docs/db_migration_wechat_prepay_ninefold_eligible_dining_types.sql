-- 夜间九折适用就餐方式（默认仅堂食）
INSERT INTO t_system_config (config_key, config_value, remark) VALUES
('wechat.prepay.ninefold.eligibleDiningTypes', '["堂食"]', '微信统一下单夜间九折适用就餐方式 JSON：堂食、打包、外卖')
ON DUPLICATE KEY UPDATE
  config_value = VALUES(config_value),
  remark = VALUES(remark);
