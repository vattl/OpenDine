-- 菜品出餐时长：KDS 单品超时优先使用本字段；无法关联菜品时回退门店 SLA。
-- NOT NULL DEFAULT 10 会让存量菜品与新增菜品统一默认为 10 分钟。
SET @dbname = DATABASE();
SET @tablename = 't_dish';
SET @columnname = 'serving_duration_minutes';
SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = @columnname) > 0,
  'SELECT ''t_dish.serving_duration_minutes already exists'' AS msg',
  'ALTER TABLE `t_dish` ADD COLUMN `serving_duration_minutes` int NOT NULL DEFAULT 10 COMMENT ''出餐时长（分钟），用于 KDS 单品超时判断'' AFTER `specification`'
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- 回滚（仅在确认没有调用方依赖该字段后手工执行）：
-- ALTER TABLE `t_dish` DROP COLUMN `serving_duration_minutes`;
