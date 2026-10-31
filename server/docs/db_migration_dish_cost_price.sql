-- 菜品成本价（可选）：用于数据分析中的单品毛利、毛利率；未维护时保持 NULL
-- 迁移完成后建议：① 去掉 Dish.cost_price 上 @TableField(exist = false)；
-- ② 将 AnalyticsMapper.xml 中 selectDishSalesAgg 的 ref_cost_price 改回 MAX(d.cost_price) AS ref_cost_price。
SET @dbname = DATABASE();
SET @tablename = 't_dish';
SET @columnname = 'cost_price';
SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = @columnname) > 0,
  'SELECT ''t_dish.cost_price already exists'' AS msg',
  'ALTER TABLE `t_dish` ADD COLUMN `cost_price` decimal(10,2) NULL DEFAULT NULL COMMENT ''成本价(元)，用于毛利分析'' AFTER `unitprice`'
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;
