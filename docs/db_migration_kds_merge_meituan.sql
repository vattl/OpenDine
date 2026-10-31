-- 美团 KDS 合并展示：门店级配置（默认开启跨单合并、堂打包内嵌、套餐合并）
ALTER TABLE `t_kds_shop_config`
  ADD COLUMN `merge_same_dish` tinyint NOT NULL DEFAULT 1 COMMENT '1=合并相同菜品（跨订单/跨桌汇总）' AFTER `lack_sets_sold_out`,
  ADD COLUMN `pack_inline_merge` tinyint NOT NULL DEFAULT 1 COMMENT '1=堂食与打包内嵌同一行；0=按渠道拆行' AFTER `merge_same_dish`,
  ADD COLUMN `combo_merge` tinyint NOT NULL DEFAULT 1 COMMENT '1=套餐子菜与散点同菜合并；0=套餐独立成行' AFTER `pack_inline_merge`;
