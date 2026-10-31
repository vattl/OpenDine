-- 菜品库存变动审计流水表 (v1.2.203)
CREATE TABLE IF NOT EXISTS `t_dish_stock_log` (
  `id` bigint AUTO_INCREMENT PRIMARY KEY,
  `shop_id` int NOT NULL COMMENT '门店ID',
  `dish_id` int NOT NULL COMMENT '菜品ID',
  `dish_name` varchar(128) DEFAULT NULL COMMENT '菜品名称',
  `order_no` varchar(64) DEFAULT NULL COMMENT '关联订单号',
  `detail_id` int DEFAULT NULL COMMENT '关联订单明细ID',
  `change_type` varchar(32) NOT NULL COMMENT '变动类型：CREATE_ORDER/ADD_DISH/CANCEL_ORDER/REFUND_RESTORE/REFUND_NO_RESTORE/REFUND_OUT_OF_STOCK/ADMIN_MANUAL/KDS_LACK',
  `delta` int NOT NULL COMMENT '变动数量(+加/-减/0不变)',
  `stock_before` int DEFAULT NULL COMMENT '变动前库存',
  `stock_after` int DEFAULT NULL COMMENT '变动后库存',
  `operator_id` varchar(64) DEFAULT NULL COMMENT '操作人/端',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注/退菜原因',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_shop_dish_time` (`shop_id`, `dish_id`, `created_at`),
  INDEX `idx_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='菜品库存变动流水日志表';
