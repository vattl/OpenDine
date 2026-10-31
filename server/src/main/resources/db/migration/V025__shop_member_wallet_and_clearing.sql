-- V025: Shop member wallet for single/chain co-existence and cross-shop balance clearing

CREATE TABLE IF NOT EXISTS `t_shop_member_wallet` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL COMMENT '用户ID',
    `shop_id` INT NOT NULL COMMENT '归属门店ID',
    `principal_balance` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '门店本金余额',
    `gift_balance` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '门店赠送余额',
    `total_recharge_principal` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '累计充值本金',
    `total_recharge_gift` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '累计赠送金额',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_user_shop` (`user_id`, `shop_id`),
    KEY `idx_shop_id` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店会员钱包分账表';

CREATE TABLE IF NOT EXISTS `t_member_cross_shop_clearing` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `order_no` VARCHAR(64) NOT NULL COMMENT '消费订单号',
    `user_id` INT NOT NULL COMMENT '会员用户ID',
    `source_shop_id` INT NOT NULL COMMENT '充值来源门店ID（出资方/债务方）',
    `consume_shop_id` INT NOT NULL COMMENT '消费发生门店ID（服务提供方/债权方）',
    `principal_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '结算本金金额',
    `gift_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '结算赠送金额',
    `total_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '结算总金额',
    `clearing_status` VARCHAR(32) NOT NULL DEFAULT 'PENDING' COMMENT '清算状态: PENDING/SETTLED',
    `settled_at` DATETIME DEFAULT NULL COMMENT '结算时间',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_order_no` (`order_no`),
    KEY `idx_source_shop` (`source_shop_id`),
    KEY `idx_consume_shop` (`consume_shop_id`),
    KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='跨店会员储值消费清算明细表';
