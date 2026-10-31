-- 营销活动弹窗预算（可选）：用于投入产出比；未维护时为 NULL
-- 迁移完成后建议：① 去掉 ActivityPopup.budget_amount 上 @TableField(exist = false)；
-- ② 将 AnalyticsMapper.xml 中 selectActivityPopupStats 的 CAST(NULL AS …) AS budget_amount 改回 IFNULL(a.budget_amount,0) AS budget_amount，且 GROUP BY 增加 a.budget_amount。
SET @dbname = DATABASE();
SET @tablename = 't_activity_popup';
SET @columnname = 'budget_amount';
SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = @columnname) > 0,
  'SELECT ''t_activity_popup.budget_amount already exists'' AS msg',
  'ALTER TABLE `t_activity_popup` ADD COLUMN `budget_amount` decimal(12,2) NULL DEFAULT NULL COMMENT ''活动投入预算(元)，用于ROI'' AFTER `is_enabled`'
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;
