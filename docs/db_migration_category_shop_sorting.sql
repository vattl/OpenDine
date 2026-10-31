-- 门店分类排序覆盖（WI-007）
-- 目的：分类主数据继续共用 t_category，但每个门店拥有独立、确定的展示顺序。
-- 上线顺序：必须先执行本迁移，再部署读取 t_category_shop 的应用版本。

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `t_category_shop` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `category_id` int NOT NULL COMMENT 't_category.id',
  `sorting_override` int NOT NULL COMMENT '当前门店分类顺序，1-based',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_category_shop` (`shop_id`,`category_id`),
  KEY `idx_category_shop_category` (`category_id`),
  CONSTRAINT `fk_category_shop_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `fk_category_shop_category` FOREIGN KEY (`category_id`) REFERENCES `t_category` (`id`)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店分类排序覆盖';

-- 无需全量回填：缺少覆盖时服务端按 t_category.sorting、t_category.id 稳定回退；
-- 某门店首次调用分类排序后，会为该店所有分类写入连续 1..n 的显式覆盖。

-- 巡检：同店不得出现重复分类行（唯一键应保证结果为 0 行）。
SELECT `shop_id`, `category_id`, COUNT(*) AS duplicate_count
FROM `t_category_shop`
GROUP BY `shop_id`, `category_id`
HAVING COUNT(*) > 1;

