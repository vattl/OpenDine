-- 工作流看板：待配菜/待制作数量化推进（分批配菜、分批制作）
ALTER TABLE `t_kds_ticket`
  ADD COLUMN `prep_quantity` int NOT NULL DEFAULT 0 COMMENT '已配菜数量（进入待制作池）' AFTER `served_quantity`,
  ADD COLUMN `cooked_quantity` int NOT NULL DEFAULT 0 COMMENT '已制作完成数量（进入待传菜池）' AFTER `prep_quantity`;
