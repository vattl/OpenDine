-- ============================================================
-- D014 支付配置渠道化：收银收款码独立开关 + 小程序支付宝支付
-- 适用：已存在 t_payment_capability 的存量库
-- 幂等说明：MySQL 8 无 ADD COLUMN IF NOT EXISTS，重复执行会报错；
--           执行前请确认列不存在（或捕获 1060 错误后仅执行 UPDATE 回填）。
-- ============================================================

ALTER TABLE `t_payment_capability`
  ADD COLUMN `cashier_wechat_qr_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端微信收款码独立开关' AFTER `offline_collect_channels`,
  ADD COLUMN `cashier_alipay_qr_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端支付宝收款码独立开关' AFTER `cashier_wechat_qr_enabled`,
  ADD COLUMN `mini_program_alipay_enabled` tinyint(4) DEFAULT NULL COMMENT '微信小程序端支付宝支付' AFTER `mini_program_balance_enabled`;

-- 回填：旧 offline_collect_channels 逗号串 → 新独立开关列
UPDATE `t_payment_capability`
SET `cashier_wechat_qr_enabled` = IF(FIND_IN_SET('wechat', `offline_collect_channels`) > 0, 1, 0),
    `cashier_alipay_qr_enabled` = IF(FIND_IN_SET('alipay', `offline_collect_channels`) > 0, 1, 0);

-- 说明：
-- 1) 写入路径（PUT /admin/payment/capabilities）此后双写：新列 + offline_collect_channels 保持兼容；
--    读取 offlineCollect.modes 兼容期间继续用 offline_collect_channels。
-- 2) offline_collect_enabled 仍为收款码总开关（默认 1）。
-- 3) mini_program_alipay_enabled 默认 0（小程序支付宝新增渠道，默认关闭）。
