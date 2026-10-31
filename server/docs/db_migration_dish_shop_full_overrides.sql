-- ============================================================================
-- 连锁门店菜品完整覆盖迁移（方案 A）
-- 目标：t_dish_shop 从「价/库存/上下架」覆盖表扩展为完整门店覆盖表，
--       门店可独立：价格 / 规格模板 / 名称 / 图片 / 单位 / 分类 / 排序 / 出餐时长。
-- 约定：所有新列 NULL = 回退总部 t_dish 对应字段；非 NULL = 门店覆盖。
--       （与既有 unitprice / onsale_override 的 NULL 回退语义一致）
-- 配套代码：DishShop 实体、AdminDishController.save/sort、DishMapper.xml 门店查询、
--           DishController.listAll applyShopOverrides、ComboMealServiceImpl.applyShopToDish。
-- 建议：低峰期执行，执行前备份 t_dish_shop。
-- 幂等：与项目迁移惯例一致，列已存在时跳过对应语句（MySQL 8.0 不支持 ADD COLUMN IF NOT EXISTS）。
-- ============================================================================

SET NAMES utf8mb4;

ALTER TABLE `t_dish_shop`
  ADD COLUMN `specification_override` varchar(255) NULL DEFAULT NULL COMMENT '门店规格模板JSON；NULL 回退 t_dish.specification' AFTER `onsale_override`,
  ADD COLUMN `name_override` varchar(50) NULL DEFAULT NULL COMMENT '门店本地化名称；NULL 回退 t_dish.name' AFTER `specification_override`,
  ADD COLUMN `image_override` varchar(50) NULL DEFAULT NULL COMMENT '门店本地化图片；NULL 回退 t_dish.image' AFTER `name_override`,
  ADD COLUMN `unit_override` varchar(10) NULL DEFAULT NULL COMMENT '门店单位；NULL 回退 t_dish.unit' AFTER `image_override`,
  ADD COLUMN `type_id_override` int NULL DEFAULT NULL COMMENT '门店分类(t_category.id)；NULL 回退 t_dish.typeId' AFTER `unit_override`,
  ADD COLUMN `sorting_override` int NULL DEFAULT NULL COMMENT '门店排序；NULL 回退 t_dish.sorting' AFTER `type_id_override`,
  ADD COLUMN `serving_duration_override` int NULL DEFAULT NULL COMMENT '门店出餐时长(分钟)；NULL 回退 t_dish.serving_duration_minutes' AFTER `sorting_override`;

-- 巡检：应返回 7 行新列
-- SELECT COLUMN_NAME FROM information_schema.COLUMNS
--  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_dish_shop'
--   AND COLUMN_NAME IN ('specification_override','name_override','image_override',
--                       'unit_override','type_id_override','sorting_override',
--                       'serving_duration_override');
