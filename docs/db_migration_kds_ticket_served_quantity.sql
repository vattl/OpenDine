-- 出餐屏分批传菜：记录已确认出餐数量，满额后 archived=1
ALTER TABLE `t_kds_ticket`
  ADD COLUMN `served_quantity` int NOT NULL DEFAULT 0 COMMENT '已传菜确认数量（分批出餐）' AFTER `archived`;
