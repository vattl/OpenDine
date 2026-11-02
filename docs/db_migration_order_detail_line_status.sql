-- 订单明细退菜状态（normal=有效 / refunded=已退菜）
ALTER TABLE `t_order_detail`
    ADD COLUMN `line_status` varchar(16) NOT NULL DEFAULT 'normal' COMMENT 'normal|refunded' AFTER `order_rece`;

ALTER TABLE `t_order_detail`
    ADD KEY `idx_order_detail_line_status` (`mId`, `line_status`);
