-- WI-074: Enhance invoice token security, add hash and expiration timestamps.

-- 1. Extend t_order_invoice with token_hash and validity lifecycle fields
ALTER TABLE `t_order_invoice`
  ADD COLUMN `token_hash` varchar(64) DEFAULT NULL COMMENT '访问token SHA-256哈希' AFTER `invoice_qr_url`,
  ADD COLUMN `token_expire_at` datetime DEFAULT NULL COMMENT 'token有效期截止时间' AFTER `token_hash`,
  ADD COLUMN `token_used_at` datetime DEFAULT NULL COMMENT 'token首次提交/使用时间' AFTER `token_expire_at`,
  ADD KEY `idx_token_hash` (`token_hash`);
