-- ============================================================
-- 支付渠道运营扩展（协调文档 §2：停用影响判定 / 支付测试交易）
-- 说明：渠道列表与启停已由既有 GET/PUT /admin/payment/capabilities 承担（本模块不重复实现）。
-- 幂等：可重复执行。已有数据零影响。
-- ============================================================

-- 1) 支付测试交易记录（幂等键唯一）
CREATE TABLE IF NOT EXISTS `t_payment_test_txn` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `channel_code` varchar(32) NOT NULL COMMENT '渠道 code（PaymentChannelCatalog）',
  `amount` decimal(10,2) NOT NULL DEFAULT 0 COMMENT '测试金额（元）',
  `terminal` varchar(64) DEFAULT NULL COMMENT '终端标识',
  `idempotency_key` varchar(64) NOT NULL COMMENT '幂等键（客户端生成）',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/DONE/FAILED',
  `charge_status` varchar(32) DEFAULT NULL COMMENT 'READINESS_OK/OFFLINE_NO_MONEY_MOVEMENT/FAILED',
  `refund_status` varchar(32) DEFAULT NULL COMMENT 'NOT_REQUIRED（未发生资金动作）',
  `error` varchar(500) DEFAULT NULL,
  `created_by` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop_idem` (`shop_id`,`idempotency_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='支付渠道测试交易';

-- 2) 权限码注册
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('payment:view',   '支付渠道查看', 'payment', '支付渠道列表/停用影响查看', 100),
('payment:manage', '支付渠道管理', 'payment', '支付渠道启停与测试交易', 101);

-- 3) 接口-权限映射
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('POST', '/admin/payment/channels/*/impact', 'payment:view|payment:manage'),
('POST', '/admin/payment/channels/*/test',   'payment:manage');

-- 4) 授权
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('payment:view','payment:manage')
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code = 'payment:view'
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
