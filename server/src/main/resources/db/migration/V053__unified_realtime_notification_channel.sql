-- WI-078: Unified Realtime Notification Channel & Dynamic Shop Prep Timeout Configuration

-- 1. Unified Realtime Notification Outbox & Inbox Table
CREATE TABLE IF NOT EXISTS `t_realtime_notification` (
  `seq_id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '全局单调递增游标ID（客户端断线增量拉取依据）',
  `message_id` varchar(64) NOT NULL COMMENT '全局唯一幂等键（如 ntf_order_paid_ORD123, ntf_timeout_ORD123_stage1）',
  `target_scope` varchar(16) NOT NULL DEFAULT 'SHOP' COMMENT '目标范围：SHOP / USER / BROADCAST',
  `shop_id` int(11) DEFAULT NULL COMMENT '目标门店ID（0表示全店）',
  `user_id` int(11) DEFAULT NULL COMMENT '目标C端用户ID',
  `user_openid` varchar(64) DEFAULT NULL COMMENT '目标C端用户OpenID',
  `client_type` varchar(32) NOT NULL DEFAULT 'CASHIER' COMMENT '目标终端类型：CASHIER / MINI_PROGRAM / ALL',
  `business_type` varchar(32) NOT NULL COMMENT '业务域：ORDER / COUPON / TABLE / KDS / MENU / TAKEOUT / SYSTEM',
  `event_type` varchar(64) NOT NULL COMMENT '事件类型：NEW_ORDER_PAID / ORDER_PREP_TIMEOUT / COUPON_GRANTED / ALERT_DISMISSED 等',
  `priority` varchar(8) NOT NULL DEFAULT 'P1' COMMENT '优先级：P0(强阻断告警) / P1(高优提醒) / P2(业务状态同步)',
  `require_ack` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否需要客户端回执确认：0否 1是',
  `display_strategy_json` text COMMENT '前端展示与播报策略JSON',
  `payload_json` text NOT NULL COMMENT '业务载荷JSON',
  `read_status` tinyint(4) NOT NULL DEFAULT 0 COMMENT '状态：0未读/待处理 1已读/已确认 2已过期',
  `acked_by` varchar(64) DEFAULT NULL COMMENT '确认处理的终端/操作员标识',
  `acked_at` datetime DEFAULT NULL COMMENT '确认处理时间',
  `expire_at` datetime NOT NULL COMMENT '消息过期时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`seq_id`),
  UNIQUE KEY `uk_message_id` (`message_id`),
  KEY `idx_shop_seq` (`shop_id`, `client_type`, `seq_id`),
  KEY `idx_user_openid_seq` (`user_openid`, `seq_id`),
  KEY `idx_expire_status` (`read_status`, `expire_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='统一实时消息与通知表';

-- 2. Per-Shop Dynamic Notification & Order Prep Timeout Configuration Table
CREATE TABLE IF NOT EXISTS `t_shop_notification_config` (
  `shop_id` int(11) NOT NULL COMMENT '门店ID（关联 t_shop.id）',
  `prep_timeout_enabled` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否开启出餐超时告警：0关闭 1开启',
  `prep_timeout_minutes` int(11) NOT NULL DEFAULT 15 COMMENT '出餐超时动态阈值（分钟，合法范围 5~120，默认15）',
  `timeout_repeat_interval_seconds` int(11) NOT NULL DEFAULT 60 COMMENT 'P0告警未确认时重复语音提醒间隔（秒，默认60）',
  `updated_by` int(11) DEFAULT NULL COMMENT '最后修改管理员ID',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店消息通知与出餐超时动态阈值配置表';

-- 3. Register API Permission Mappings for Unified Notification Channel & Shop Timeout Config
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('GET', '/admin/shop/notification-config', 'shop:manage|order:config|settings:view|cashier:operate', '查询门店消息与出餐超时动态阈值配置'),
('*', '/admin/shop/notification-config', 'shop:manage|order:config|settings:manage|cashier:operate', '查询/保存门店消息与出餐超时动态阈值配置'),
('PUT', '/admin/shop/notification-config', 'shop:manage|order:config|settings:manage', '修改门店消息与出餐超时动态阈值配置'),
('GET', '/cashier/notifications/sync', 'cashier:operate|order:view', '收银端断线重连增量同步未读实时消息'),
('*', '/cashier/notifications/sync', 'cashier:operate|order:view', '收银端断线重连增量同步未读实时消息'),
('POST', '/cashier/notifications/ack', 'cashier:operate|order:operate', '收银端确认消息已读并跨终端消除告警'),
('*', '/cashier/notifications/ack', 'cashier:operate|order:operate', '收银端确认消息已读并跨终端消除告警'),
('GET', '/api/v1/notifications/sync', 'cashier:operate|order:view', '统一消息通道增量同步未读实时消息'),
('*', '/api/v1/notifications/sync', 'cashier:operate|order:view', '统一消息通道增量同步未读实时消息'),
('POST', '/api/v1/notifications/ack', 'cashier:operate|order:operate', '统一消息通道确认消息已读并消除告警'),
('*', '/api/v1/notifications/ack', 'cashier:operate|order:operate', '统一消息通道确认消息已读并消除告警')
ON DUPLICATE KEY UPDATE `permission_code` = VALUES(`permission_code`), `remark` = VALUES(`remark`);
