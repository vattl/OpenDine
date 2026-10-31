-- ============================================================================
-- db_migration_payment_qr_enabled_sync.sql
-- 收款码总闸联动存量修复（D020 修复）
-- 背景：D014 起收款码独立开关（cashier_wechat_qr_enabled / cashier_alipay_qr_enabled），
--       但 PUT 双写只更新 offline_collect_channels，未联动 legacy 总闸 offline_collect_enabled；
--       历史已开启收款码的门店该列为 0，收银端读 channels.offlineCollect.enabled 误判「收款码未启用」。
-- 本脚本：一次性回填——任一收款码已开启但总闸为 0 的行置 1。
-- 幂等：重复执行无副作用。
-- 执行：mysql -u<user> -p db_diancan < db_migration_payment_qr_enabled_sync.sql
-- ============================================================================

UPDATE t_payment_capability
SET offline_collect_enabled = 1
WHERE offline_collect_enabled = 0
  AND (cashier_wechat_qr_enabled = 1 OR cashier_alipay_qr_enabled = 1);
