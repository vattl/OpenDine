-- ============================================================================
-- t_admin 员工状态/权限版本/强制下线 列迁移（POS Access Control v2）
-- 背景：员工状态变更接口 PUT /admin/access/employees/{adminId}/status 写入
--       t_admin.account_status / permission_version / force_logout_at；
--       此前这三列只在设计文档（POS权限中心升级_技术落地设计_v1.0.md）出现，
--       未提供独立可执行迁移脚本。若线上表缺列，接口会直接报错或写入失败，
--       表现为「返回成功但状态不变 / 更新未生效」。
-- 目标：幂等补齐三列（token_version 见 db_migration_admin_token_version.sql）。
-- 幂等：基于 information_schema 判断，可重复执行；列已存在时跳过。
-- 执行：先跑本脚本，再部署新 JAR。
-- ============================================================================

SET NAMES utf8mb4;

-- 1) account_status：账号状态 ACTIVE/DISABLED/LOCKED/RESIGNED
SET @col_exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                    WHERE table_schema = DATABASE() AND table_name = 't_admin'
                      AND column_name = 'account_status');
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE `t_admin` ADD COLUMN `account_status` VARCHAR(20) NOT NULL DEFAULT ''ACTIVE'' COMMENT ''账号状态: ACTIVE/DISABLED/LOCKED/RESIGNED'' AFTER `token_version`',
  'SELECT ''account_status already exists'' AS msg');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 2) permission_version：权限版本号，角色/状态变更时递增，旧会话权限缓存失效
SET @col_exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                    WHERE table_schema = DATABASE() AND table_name = 't_admin'
                      AND column_name = 'permission_version');
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE `t_admin` ADD COLUMN `permission_version` BIGINT NOT NULL DEFAULT 1 COMMENT ''权限版本号，变更时递增'' AFTER `account_status`',
  'SELECT ''permission_version already exists'' AS msg');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 3) force_logout_at：强制下线时间，签发早于此时的 JWT 失效
SET @col_exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                    WHERE table_schema = DATABASE() AND table_name = 't_admin'
                      AND column_name = 'force_logout_at');
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE `t_admin` ADD COLUMN `force_logout_at` DATETIME NULL COMMENT ''强制下线时间，签发早于此时的JWT失效'' AFTER `permission_version`',
  'SELECT ''force_logout_at already exists'' AS msg');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 4) token_version：会话撤销版本（如缺失一并补齐，见 db_migration_admin_token_version.sql）
SET @col_exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                    WHERE table_schema = DATABASE() AND table_name = 't_admin'
                      AND column_name = 'token_version');
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE `t_admin` ADD COLUMN `token_version` INT NOT NULL DEFAULT 0 COMMENT ''管理员令牌版本，递增后旧令牌立即失效'' AFTER `password`',
  'SELECT ''token_version already exists'' AS msg');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 终检：确认四列齐备
SELECT column_name, column_type, is_nullable, column_default, column_comment
FROM information_schema.COLUMNS
WHERE table_schema = DATABASE() AND table_name = 't_admin'
  AND column_name IN ('token_version', 'account_status', 'permission_version', 'force_logout_at')
ORDER BY ordinal_position;
