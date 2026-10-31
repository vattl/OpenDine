-- ============================================================================
-- db_migration_user_list_perf.sql
-- 用户列表接口（POST /admin/order/getUserInfo）性能优化迁移（D020，方案 A 索引）
-- 目标：pageUserListWithStats 由「每行相关子查询 + transac_status 全表过滤」
--       变为「预聚合 JOIN + 索引范围扫描」（方案 B 已在 UserMapper.xml 落地）。
-- 本脚本仅含索引（幂等：已存在则跳过），MySQL 8.0 兼容。
-- 执行：mysql -u<user> -p db_diancan < db_migration_user_list_perf.sql
-- 校验：SHOW INDEX FROM t_order; SHOW INDEX FROM t_invite_record; SHOW INDEX FROM t_user_coupon;
-- ============================================================================

SET @db = DATABASE();

-- 1) t_order：transac_status 前缀 + openid/pay_openid + pay_time 覆盖索引
--    - 聚合/最近消费预聚合的 openid 分支：WHERE transac_status='success' ... GROUP BY openid / MAX(pay_time)
--    - pay_openid 分支同理（pay_openid 为 varbinary(255)，索引列类型以表定义为准）
SET @s = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_order ADD KEY idx_order_status_openid_time (transac_status, openid, pay_time)',
  'SELECT ''idx_order_status_openid_time exists, skip''')
  FROM information_schema.statistics
  WHERE table_schema = @db AND table_name = 't_order' AND index_name = 'idx_order_status_openid_time');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @s = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_order ADD KEY idx_order_status_payopenid_time (transac_status, pay_openid, pay_time)',
  'SELECT ''idx_order_status_payopenid_time exists, skip''')
  FROM information_schema.statistics
  WHERE table_schema = @db AND table_name = 't_order' AND index_name = 'idx_order_status_payopenid_time');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- 2) t_invite_record：邀请人 openid 索引（邀请注册数预聚合 GROUP BY inviter_openid）
SET @s = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_invite_record ADD KEY idx_inviter_openid (inviter_openid)',
  'SELECT ''idx_inviter_openid exists, skip''')
  FROM information_schema.statistics
  WHERE table_schema = @db AND table_name = 't_invite_record' AND index_name = 'idx_inviter_openid');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- 3) t_user_coupon：用户券可用数预聚合 (user_openid, status)
SET @s = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_user_coupon ADD KEY idx_user_openid_status (user_openid, status)',
  'SELECT ''idx_user_openid_status exists, skip''')
  FROM information_schema.statistics
  WHERE table_schema = @db AND table_name = 't_user_coupon' AND index_name = 'idx_user_openid_status');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- 回滚（如需）：DROP INDEX idx_order_status_openid_time ON t_order; 等
