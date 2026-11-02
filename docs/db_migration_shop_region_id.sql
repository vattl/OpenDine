-- 仅补齐 t_shop.region_id（修复登录/门店列表报 Unknown column 'region_id'）
-- 适用：已执行连锁门店补丁（含 sort_order、remark、latitude、longitude）但未执行区域迁移的库。
-- 若需完整 P3（t_region、t_admin_region、门店区域绑定），请改执行 docs/db_migration_admin_region.sql（其中已包含本列，勿重复执行本文件）。
-- 若列或索引已存在，对应语句会报错，可忽略该行。
-- 登录若报 t_admin_region 不存在，请继续执行 docs/db_migration_admin_region_tables_only.sql（或完整 db_migration_admin_region.sql）。

SET NAMES utf8mb4;

ALTER TABLE `t_shop`
  ADD COLUMN `region_id` int NULL DEFAULT NULL COMMENT '区域ID，关联 t_region.id' AFTER `code`;

ALTER TABLE `t_shop`
  ADD KEY `idx_shop_region` (`region_id`);
