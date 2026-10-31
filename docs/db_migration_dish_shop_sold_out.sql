-- Shop-level sold-out flag for dishes.
-- Keeps API response field name as sold_out, but stores and updates it per shop.
-- Safe to run more than once on MySQL 5.7/8.0.

SET NAMES utf8mb4;

SET @col_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 't_dish_shop'
    AND COLUMN_NAME = 'sold_out'
);

SET @ddl := IF(
  @col_exists = 0,
  'ALTER TABLE `t_dish_shop` ADD COLUMN `sold_out` tinyint NOT NULL DEFAULT 0 COMMENT ''shop sold-out flag: 0 available, 1 sold out'' AFTER `stock`',
  'SELECT ''t_dish_shop.sold_out already exists'' AS msg'
);

PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Normalize existing shop links so later on/off-sale operations are shop isolated.
UPDATE `t_dish_shop` ds
JOIN `t_dish` d ON d.`id` = ds.`dish_id`
SET ds.`onsale_override` = IF(d.`onsale`, 1, 0)
WHERE ds.`onsale_override` IS NULL;

