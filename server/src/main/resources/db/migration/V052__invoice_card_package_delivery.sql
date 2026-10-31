-- WI-075 / WeChat Pay Invoice Card Package: Extend invoice table with card insertion fields and permissions

-- 1. Extend t_order_invoice with card insertion fields
ALTER TABLE `t_order_invoice`
  ADD COLUMN `card_id` varchar(64) DEFAULT NULL COMMENT '微信发票卡券模板ID' AFTER `fapiao_file_url`,
  ADD COLUMN `card_code` varchar(64) DEFAULT NULL COMMENT '微信卡包卡券Code' AFTER `card_id`,
  ADD COLUMN `fapiao_media_id` varchar(128) DEFAULT NULL COMMENT '微信发票文件媒体ID' AFTER `card_code`,
  ADD COLUMN `card_insert_status` varchar(32) NOT NULL DEFAULT 'NOT_ATTEMPTED' COMMENT '卡包插卡状态: NOT_ATTEMPTED, PENDING, SUCCESS, FAILED' AFTER `fapiao_media_id`,
  ADD COLUMN `card_insert_msg` varchar(512) DEFAULT NULL COMMENT '卡包插卡结果说明/错误原因' AFTER `card_insert_status`,
  ADD COLUMN `card_inserted_at` datetime DEFAULT NULL COMMENT '卡包插入完成时间' AFTER `card_insert_msg`;

-- 2. Register endpoint permission mapping for manual card insertion retry
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('POST', '/admin/order/invoice/insert-card', 'order:operate|order:invoice:operate', '财务后台发票手动重试推送到用户卡包'),
('*', '/admin/order/invoice/insert-card', 'order:operate|order:invoice:operate', '财务后台发票手动重试推送到用户卡包')
ON DUPLICATE KEY UPDATE `permission_code` = VALUES(`permission_code`), `remark` = VALUES(`remark`);
