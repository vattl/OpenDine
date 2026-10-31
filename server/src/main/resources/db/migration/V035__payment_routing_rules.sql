-- WI-036: Multi-condition merchant routing rules
CREATE TABLE IF NOT EXISTS `t_payment_routing_rule` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `shop_id` INT NOT NULL COMMENT '门店ID，0为全店模板',
  `channel` VARCHAR(20) NOT NULL DEFAULT 'wechat' COMMENT '支付渠道: wechat/alipay',
  `rule_name` VARCHAR(64) NOT NULL COMMENT '规则名称',
  `priority` INT NOT NULL DEFAULT 100 COMMENT '执行优先级：数字越大越先匹配',
  `enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用: 1启用 0停用',
  `target_merchant_key` VARCHAR(32) NOT NULL COMMENT '目标商户Key (如: small_amount, default)',
  `match_mode` VARCHAR(10) NOT NULL DEFAULT 'ALL' COMMENT '条件关系: ALL(所有条件必须同时满足/AND), ANY(任一满足/OR)',
  `conditions_json` JSON NOT NULL COMMENT '具体多条件配置JSON',
  `remark` VARCHAR(255) DEFAULT NULL COMMENT '备注说明',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shop_channel_priority` (`shop_id`, `channel`, `priority`, `enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店支付分流路由规则表';

-- 注册支付路由规则API权限
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('*', '/admin/payment/routing-rules', 'payment:config:read|payment:config:write', '商户分流路由规则-列表与创建'),
('*', '/admin/payment/routing-rules/', 'payment:config:read|payment:config:write', '商户分流路由规则-详情与编辑删除'),
('*', '/admin/payment/routing-rules/sort', 'payment:config:write', '商户分流路由规则-优先级重排'),
('*', '/admin/payment/routing-rules/simulate', 'payment:config:read', '商户分流路由规则-模拟测算')
ON DUPLICATE KEY UPDATE `permission_code` = VALUES(`permission_code`), `remark` = VALUES(`remark`);