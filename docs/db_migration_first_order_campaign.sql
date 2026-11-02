-- ============================================================
-- 首单活动营销模块（协调文档 §2：活动列表/保存/资格判定/核销记录）
-- 幂等：可重复执行。已有数据零影响。
-- ============================================================

-- 1) 首单活动
CREATE TABLE IF NOT EXISTS `t_first_order_campaign` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `name` varchar(128) NOT NULL COMMENT '活动名称',
  `campaign_type` varchar(32) NOT NULL COMMENT 'DISCOUNT=立减 / GIFT=赠品 / FREEBIE=首单免费',
  `threshold_amount` decimal(10,2) NOT NULL DEFAULT 0 COMMENT '门槛金额（元）',
  `discount_value` decimal(10,2) NOT NULL DEFAULT 0 COMMENT '优惠金额/折让（元）',
  `discount_desc` varchar(255) DEFAULT NULL COMMENT '优惠描述',
  `start_time` datetime NOT NULL COMMENT '生效时间',
  `end_time` datetime NOT NULL COMMENT '失效时间',
  `status` varchar(16) NOT NULL DEFAULT 'DRAFT' COMMENT 'DRAFT/ACTIVE/PAUSED/EXPIRED',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shop_status` (`shop_id`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='首单活动';

-- 2) 首单核销/恢复记录
CREATE TABLE IF NOT EXISTS `t_first_order_redemption` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `campaign_id` bigint NOT NULL COMMENT 't_first_order_campaign.id',
  `customer_id` varchar(128) NOT NULL COMMENT '客户标识（openid 或手机号）',
  `order_no` varchar(64) DEFAULT NULL,
  `order_id` int DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL DEFAULT 0 COMMENT '实享优惠金额（元）',
  `status` varchar(16) NOT NULL DEFAULT 'USED' COMMENT 'USED=已核销 / RESTORED=已恢复',
  `restored_reason` varchar(32) DEFAULT NULL COMMENT 'cancel/full_refund/manual',
  `restored_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_shop_customer` (`shop_id`,`customer_id`),
  KEY `idx_shop_campaign` (`shop_id`,`campaign_id`),
  KEY `idx_order` (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='首单核销记录';

-- 3) 权限码注册
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('marketing:firstorder:view',   '首单活动查看', 'marketing', '首单活动列表/资格判定/核销记录查看', 80),
('marketing:firstorder:manage', '首单活动管理', 'marketing', '首单活动创建与更新', 81);

-- 4) 接口-权限映射
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',  '/admin/marketing/first-order/campaigns',              'marketing:firstorder:view|marketing:firstorder:manage'),
('POST', '/admin/marketing/first-order/campaigns',              'marketing:firstorder:manage'),
('PUT',  '/admin/marketing/first-order/campaigns/*',            'marketing:firstorder:manage'),
('POST', '/admin/marketing/first-order/eligibility/evaluate',   'marketing:firstorder:view|marketing:firstorder:manage'),
('GET',  '/admin/marketing/first-order/redemptions',            'marketing:firstorder:view|marketing:firstorder:manage');

-- 5) 授权
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('marketing:firstorder:view','marketing:firstorder:manage')
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code = 'marketing:firstorder:view'
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
