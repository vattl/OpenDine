-- WI-072: Complete API permission mappings, introduce fine-grained permissions and invoice table.

-- 0. Ensure table t_order_invoice exists
CREATE TABLE IF NOT EXISTS `t_order_invoice` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `order_no` varchar(64) NOT NULL COMMENT '订单号',
  `shop_id` int(11) NOT NULL DEFAULT '1' COMMENT '门店ID',
  `fapiao_apply_id` varchar(64) NOT NULL COMMENT '发票申请单号（唯一标识一次开票申请）',
  `invoice_status` varchar(32) NOT NULL DEFAULT 'PENDING_SCAN' COMMENT '开票状态: PENDING_SCAN-待扫码填抬头, TITLE_SUBMITTED-抬头已提交, ISSUING-开票中, SUCCESS-开票成功, FAILED-开票失败, REVERSED-已冲红',
  `invoice_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '申请开票金额(元)',
  `tax_rate` decimal(5,4) NOT NULL DEFAULT '0.0600' COMMENT '税率，默认0.06',
  `invoice_qr_url` varchar(512) DEFAULT NULL COMMENT '顾客开票二维码链接',
  `buyer_title` varchar(128) DEFAULT NULL COMMENT '购方抬头名称（企业或个人）',
  `buyer_tax_no` varchar(64) DEFAULT NULL COMMENT '购方税号/纳税人识别号',
  `buyer_phone` varchar(32) DEFAULT NULL COMMENT '购方手机号',
  `buyer_email` varchar(128) DEFAULT NULL COMMENT '购方接收发票邮箱',
  `fapiao_number` varchar(64) DEFAULT NULL COMMENT '发票号码',
  `fapiao_code` varchar(64) DEFAULT NULL COMMENT '发票代码',
  `fapiao_file_url` varchar(512) DEFAULT NULL COMMENT '电子发票PDF/OFD文件下载链接',
  `operator_id` int(11) DEFAULT NULL COMMENT '触发开票的收银员/操作人ID',
  `error_msg` varchar(255) DEFAULT NULL COMMENT '开票失败原因',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fapiao_apply_id` (`fapiao_apply_id`),
  KEY `idx_order_no` (`order_no`),
  KEY `idx_shop_status` (`shop_id`, `invoice_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单电子发票开具申请表';

-- 1. Ensure fine-grained permissions exist in dictionary t_permission
INSERT IGNORE INTO `t_permission`
(`permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
('dish:manage:combo', '套餐管理', '菜品', '套餐关联查询、保存与门店隔离维护', 44),
('order:invoice:create', '开具电子发票', '订单', '生成发票二维码与开具操作', 30),
('order:invoice:view', '查询发票状态', '订单', '查看电子发票开具状态与日志', 31),
('daily:view', '日结数据查看', '对账', '日结上下文、汇总与Z-Report查看', 35),
('reconciliation:view', '渠道对账查看', '对账', '渠道对账概览、批次与差异案例查看', 36),
('reconciliation:operate', '渠道对账操作', '对账', '账单导入与差异处理', 37);

-- 2. Bind newly introduced permissions to super_admin and admin roles
INSERT IGNORE INTO `t_role_permission` (`role_id`, `permission_id`)
SELECT role_row.id, permission_row.id
FROM `t_role` role_row
JOIN `t_permission` permission_row ON permission_row.permission_code IN (
  'dish:manage:combo',
  'order:invoice:create',
  'order:invoice:view',
  'daily:view',
  'reconciliation:view',
  'reconciliation:operate',
  'marketing:firstorder:view',
  'marketing:firstorder:manage',
  'inventory:view',
  'inventory:manage',
  'payment:view',
  'payment:manage',
  'report:export',
  'log:archive',
  'log:export',
  'notifications:view',
  'notifications:manage',
  'settings:view',
  'settings:manage'
)
WHERE role_row.role_code IN (
  'super_admin', 'owner', 'admin', 'boss', 'store_manager', 'shop_manager', 'shop_admin'
);

-- 3. Upsert newly audited routes into t_api_permission
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`) VALUES
-- 套餐细粒度
('*', '/admin/combo/getByDishId', 'dish:manage|dish:manage:dish|dish:manage:combo'),
('*', '/admin/combo/save', 'dish:manage|dish:manage:dish|dish:manage:combo'),
-- 发票与订单
('*', '/admin/order/invoice/qrcode', 'order:operate|order:invoice:create'),
('*', '/admin/order/invoice/status/', 'order:view|order:invoice:view'),
('*', '/admin/order/audit-timeline/', 'order:view'),
('*', '/admin/order/updateDiners', 'cashier:operate|order:operate'),
('*', '/admin/order/commands', 'cashier:operate|order:operate'),
('*', '/admin/merchant/orders', 'order:view'),
('*', '/admin/merchant/orders/summary', 'order:view'),
-- 会员与桌台历史未入迁移路径
('*', '/admin/member/list', 'user:view'),
('*', '/admin/table/qrcode', 'table:manage|cashier:operate|table:operate'),
-- 营销与首单活动
('*', '/admin/marketing/first-order/campaigns', 'marketing:firstorder:view|marketing:firstorder:manage'),
('*', '/admin/marketing/first-order/campaigns/', 'marketing:firstorder:manage'),
('*', '/admin/marketing/first-order/eligibility/evaluate', 'marketing:firstorder:view'),
('*', '/admin/marketing/first-order/redemptions', 'marketing:firstorder:view'),
-- 高级库存
('*', '/admin/inventory/batches', 'inventory:view'),
('*', '/admin/inventory/boms', 'inventory:view|inventory:manage'),
('*', '/admin/inventory/boms/', 'inventory:manage'),
('*', '/admin/inventory/purchases', 'inventory:view|inventory:manage'),
('*', '/admin/inventory/purchases/', 'inventory:manage'),
('*', '/admin/inventory/suppliers', 'inventory:view|inventory:manage'),
('*', '/admin/inventory/suppliers/', 'inventory:manage'),
('*', '/admin/inventory/transfers', 'inventory:view|inventory:manage'),
('*', '/admin/inventory/transfers/', 'inventory:manage'),
('*', '/admin/inventory/warehouses', 'inventory:view|inventory:manage'),
('*', '/admin/inventory/warehouses/', 'inventory:manage'),
-- 日志归档与导出
('*', '/admin/logs', 'log:view'),
('*', '/admin/logs/archive-search', 'log:archive'),
('*', '/admin/logs/archive-search/', 'log:archive'),
('*', '/admin/logs/exports', 'log:export'),
-- 通知规则
('*', '/admin/notifications/rules', 'notifications:view|notifications:manage'),
('*', '/admin/notifications/rules/', 'notifications:manage'),
('*', '/admin/notifications/deliveries', 'notifications:view'),
-- 报表导出与跨店结算
('*', '/admin/reports/exports', 'report:export'),
('*', '/admin/reports/exports/', 'report:export'),
('*', '/admin/report/member/cross-shop-clearing', 'report:view|finance:view'),
-- 系统设置与多店配置
('*', '/admin/settings/overview', 'settings:view'),
('*', '/admin/settings/store', 'settings:view|settings:manage'),
('*', '/admin/settings/store/override', 'settings:manage'),
('*', '/admin/config/member-balance-cross-shop', 'shop:manage|admin:manage'),
-- 支付渠道运营
('*', '/admin/payment/channels/', 'payment:view|payment:manage'),
-- 会员画像标签
('*', '/admin/member/persona-tags', 'user:view'),
-- 收银端与POS别名
('*', '/cashier/shop/business', 'cashier:operate|shop:manage'),
('*', '/api/pos/orders/hang-list', 'cashier:operate'),
('*', '/api/pos/hang-list', 'cashier:operate'),
('*', '/api/pos/orders/today', 'cashier:operate'),
('*', '/api/pos/today', 'cashier:operate'),
('*', '/api/pos/orders/search', 'cashier:operate'),
('*', '/api/pos/search', 'cashier:operate'),
('*', '/api/pos/orders/printContent', 'cashier:operate'),
('*', '/api/pos/printContent', 'cashier:operate'),
('*', '/api/pos/tables/open', 'cashier:operate|table:operate'),
('*', '/api/pos/open', 'cashier:operate|table:operate'),
('*', '/api/pos/tables/merge', 'cashier:operate|table:operate'),
('*', '/api/pos/merge', 'cashier:operate|table:operate'),
('*', '/api/pos/tables/transfer', 'cashier:operate|table:operate'),
('*', '/api/pos/transfer', 'cashier:operate|table:operate'),
('*', '/api/pos/tables/clear', 'cashier:operate|table:operate'),
('*', '/api/pos/clear', 'cashier:operate|table:operate'),
('*', '/api/pos/tables/statusMap', 'cashier:operate'),
('*', '/api/pos/statusMap', 'cashier:operate'),
('*', '/cashier/table/table-areas', 'cashier:operate|table:view'),
('*', '/cashier/table/tables/areas', 'cashier:operate|table:view'),
('*', '/api/pos/tables/areas', 'cashier:operate|table:view'),
('*', '/api/pos/tables/table-areas', 'cashier:operate|table:view'),
('*', '/api/pos/tables/tables/areas', 'cashier:operate|table:view'),
('*', '/api/pos/areas', 'cashier:operate|table:view'),
('*', '/cashier/table/tables/batch-clear', 'cashier:operate|table:operate'),
('*', '/api/pos/tables/tables/batch-clear', 'cashier:operate|table:operate'),
('*', '/api/pos/batch-clear', 'cashier:operate|table:operate'),
('*', '/cashier/table/tables/pulse', 'cashier:operate|table:view'),
('*', '/api/pos/tables/tables/pulse', 'cashier:operate|table:view'),
('*', '/api/pos/pulse', 'cashier:operate|table:view'),
-- 活动历史接口
('*', '/activity/getAllPopup', 'banner:manage'),
-- 飞鹅云接口
('*', '/api/feieyun/print', 'printing:manage|cashier:operate'),
('*', '/api/feieyun/print-label', 'printing:manage|cashier:operate'),
('*', '/api/feieyun/order-status', 'printing:manage|cashier:operate'),
('*', '/api/feieyun/printer-status', 'printing:manage|cashier:operate'),
('*', '/api/feieyun/add-printer', 'printing:manage')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code);
