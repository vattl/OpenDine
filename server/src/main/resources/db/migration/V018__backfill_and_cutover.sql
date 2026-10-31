-- V018: 历史账本回填与双写影子验证支持 (POS-SDC-501 & POS-SDC-502)

-- 1. 为 t_payment_ledger 增加 source 与 trust_level 字段（幂等添加）
SET @dbname = DATABASE();
SET @tablename = 't_payment_ledger';

SET @preparedStatement = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @dbname
      AND TABLE_NAME = @tablename
      AND COLUMN_NAME = 'source'
  ) > 0,
  'SELECT 1',
  'ALTER TABLE `t_payment_ledger` ADD COLUMN `source` VARCHAR(32) NOT NULL DEFAULT ''NATIVE'' COMMENT ''数据来源：NATIVE/BACKFILLED_ORDER/MANUAL'' AFTER `status`'
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @dbname
      AND TABLE_NAME = @tablename
      AND COLUMN_NAME = 'trust_level'
  ) > 0,
  'SELECT 1',
  'ALTER TABLE `t_payment_ledger` ADD COLUMN `trust_level` VARCHAR(32) NOT NULL DEFAULT ''TRUST_HIGH'' COMMENT ''可信等级：TRUST_HIGH/TRUST_MEDIUM/TRUST_SUSPECT'' AFTER `source`'
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- 2. 创建历史账本回填执行日志表 t_ledger_backfill_log
CREATE TABLE IF NOT EXISTS `t_ledger_backfill_log` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '自增主键',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `stat_date` VARCHAR(10) DEFAULT NULL COMMENT '指定回填营业日(YYYY-MM-DD)，为NULL表示历史全量',
  `dry_run` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否为演练预览模式(1是 0否)',
  `total_orders_scanned` INT NOT NULL DEFAULT 0 COMMENT '扫描订单总数',
  `backfilled_orders` INT NOT NULL DEFAULT 0 COMMENT '成功回填订单数',
  `skipped_orders` INT NOT NULL DEFAULT 0 COMMENT '跳过(已存在)订单数',
  `total_rows_inserted` INT NOT NULL DEFAULT 0 COMMENT '插入账本流水总行数',
  `total_amount_fen` BIGINT NOT NULL DEFAULT 0 COMMENT '回填总金额(分)',
  `anomalies_count` INT NOT NULL DEFAULT 0 COMMENT '异常订单数(金额不符或缺少归属)',
  `anomalies_json` MEDIUMTEXT DEFAULT NULL COMMENT '异常订单明细JSON',
  `integrity_hash` VARCHAR(64) NOT NULL COMMENT 'SHA-256摘要防篡改哈希',
  `executed_by` INT DEFAULT NULL COMMENT '执行管理员ID',
  `executed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '执行时间',
  PRIMARY KEY (`id`),
  KEY `idx_backfill_shop_date` (`shop_id`, `stat_date`, `executed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='历史账本回填审计日志表' ROW_FORMAT=DYNAMIC;
