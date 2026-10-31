-- WI-079: Wechat Controllable Subscribe Message System (Scene Templates, User Quota Ledger, and Send Audit Logs)

-- 1. Subscribe Scene Template Configuration Table
CREATE TABLE IF NOT EXISTS `t_subscribe_scene_template` (
  `id` int(11) NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `scene_code` varchar(32) NOT NULL COMMENT '场景编码：ORDER_PICKUP, ORDER_STATUS, COUPON_EXPIRING, QUEUE_CALL 等',
  `template_id` varchar(64) NOT NULL COMMENT '微信订阅消息模板ID',
  `title` varchar(64) NOT NULL COMMENT '模板显示标题',
  `trigger_point` varchar(64) DEFAULT 'SUBMIT_ORDER' COMMENT '建议唤起节点：SUBMIT_ORDER, PAY_SUCCESS, QUEUE_GET_NO 等',
  `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否启用：0禁用 1启用',
  `param_mapping_json` text COMMENT '参数键映射规范配置JSON',
  `remark` varchar(255) DEFAULT NULL COMMENT '场景备注说明',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_scene_code` (`scene_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信订阅消息场景与模板配置表';

-- 2. User Subscribe Message Quota Ledger Table
CREATE TABLE IF NOT EXISTS `t_user_subscribe_quota` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '配额自增ID',
  `openid` varchar(64) NOT NULL COMMENT '微信用户OpenID',
  `scene_code` varchar(32) NOT NULL COMMENT '业务场景编码',
  `template_id` varchar(64) NOT NULL COMMENT '微信模板ID',
  `available_quota` int(11) NOT NULL DEFAULT 0 COMMENT '可用推送剩余额度（一次性订阅每同意一次+1，推送消耗-1）',
  `accept_count` int(11) NOT NULL DEFAULT 0 COMMENT '累计用户同意授权次数',
  `reject_count` int(11) NOT NULL DEFAULT 0 COMMENT '累计用户拒绝授权次数',
  `ban_status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否已被用户设为总是保持拒绝(ban)：0否 1是',
  `last_authorized_at` datetime DEFAULT NULL COMMENT '最近一次授权时间',
  `last_sent_at` datetime DEFAULT NULL COMMENT '最近一次推送时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '首次记录时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_scene_tmpl` (`openid`, `scene_code`, `template_id`),
  KEY `idx_openid_scene` (`openid`, `scene_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户微信订阅消息可用额度与台账表';

-- 3. Subscribe Message Send Audit Log Table
CREATE TABLE IF NOT EXISTS `t_subscribe_send_log` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '日志ID',
  `biz_no` varchar(64) DEFAULT NULL COMMENT '业务单号（如订单号 order_no）',
  `openid` varchar(64) NOT NULL COMMENT '目标用户OpenID',
  `scene_code` varchar(32) NOT NULL COMMENT '业务场景编码',
  `template_id` varchar(64) NOT NULL COMMENT '使用的微信模板ID',
  `send_status` varchar(16) NOT NULL COMMENT '发送状态：SUCCESS / FAILED / SKIPPED_NO_QUOTA',
  `errcode` int(11) DEFAULT 0 COMMENT '微信接口返回错误码（0为成功，43101为额度耗尽）',
  `errmsg` varchar(255) DEFAULT NULL COMMENT '微信接口返回错误描述',
  `quota_before` int(11) DEFAULT 0 COMMENT '发送前台账配额',
  `quota_after` int(11) DEFAULT 0 COMMENT '发送后台账配额',
  `duration_ms` bigint(20) DEFAULT 0 COMMENT '接口调用耗时(毫秒)',
  `payload_summary` text COMMENT '发送载荷摘要',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '发送时间',
  PRIMARY KEY (`id`),
  KEY `idx_biz_no` (`biz_no`),
  KEY `idx_openid_created` (`openid`, `created_at`),
  KEY `idx_scene_status` (`scene_code`, `send_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信订阅消息发送审计与调用日志表';

-- 4. Initialize Core Subscribe Scenes
INSERT INTO `t_subscribe_scene_template` (`scene_code`, `template_id`, `title`, `trigger_point`, `is_active`, `remark`) VALUES
('ORDER_PICKUP', 'order_pickup_template_id_placeholder_001', '取餐通知', 'SUBMIT_ORDER', 1, '全单出餐完成时通知顾客前往取餐'),
('ORDER_STATUS', '7t69W_Uq212bO1uH8mUu4t2zGk0_1234567890abcdef', '接单制作通知', 'SUBMIT_ORDER', 1, '后厨接单并开始备餐时通知顾客'),
('COUPON_EXPIRING', 'c0up0n_expiring_template_id_placeholder_001', '优惠券到期提醒', 'PAY_SUCCESS', 1, '优惠券临近过期前提醒顾客核销使用')
ON DUPLICATE KEY UPDATE `template_id` = VALUES(`template_id`), `title` = VALUES(`title`), `trigger_point` = VALUES(`trigger_point`);

-- 5. Register Admin API Permissions for Subscribe Message Management
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('GET', '/admin/subscribe/scenes', 'settings:view|order:view', '查询微信订阅消息场景与模板配置列表'),
('PUT', '/admin/subscribe/scenes/*', 'settings:manage|order:operate', '修改微信订阅消息场景与模板配置'),
('GET', '/admin/subscribe/logs', 'settings:view|order:view', '查询微信订阅消息发送审计日志'),
('*', '/admin/subscribe/**', 'settings:manage|order:operate', '微信订阅消息管理后台通用权限')
ON DUPLICATE KEY UPDATE `permission_code` = VALUES(`permission_code`), `remark` = VALUES(`remark`);
