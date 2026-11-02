-- ======================================================================
-- 增量迁移脚本：个人收款（支付宝/微信 App 监听）通知事件记录表
-- ======================================================================

CREATE TABLE IF NOT EXISTS `t_personal_payment_event` (
    `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `event_id` VARCHAR(128) NOT NULL COMMENT '客户端/App 唯一事件 ID（幂等主键）',
    `channel` VARCHAR(32) NOT NULL COMMENT '收款渠道（alipay / wechat）',
    `amount_fen` BIGINT NOT NULL COMMENT '到账金额（分）',
    `amount_yuan` DECIMAL(10, 2) NOT NULL COMMENT '到账金额（元）',
    `timestamp_raw` VARCHAR(64) NULL DEFAULT NULL COMMENT '原始时间戳',
    `raw_text` TEXT NULL COMMENT '原始到账通知文本内容',
    `matched_shop_id` INT NULL DEFAULT NULL COMMENT '自动匹配到的门店 ID',
    `matched_order_no` VARCHAR(64) NULL DEFAULT NULL COMMENT '自动匹配到的订单号',
    `status` VARCHAR(32) NOT NULL DEFAULT 'PROCESSED' COMMENT '处理状态（PROCESSED已处理，MATCHED已核销，UNMATCHED未匹配）',
    `remark` VARCHAR(255) NULL DEFAULT NULL COMMENT '处理结果与备注',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_personal_pay_event_id` (`event_id`),
    KEY `idx_personal_pay_created` (`created_at`),
    KEY `idx_personal_pay_matched_order` (`matched_order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='个人收款 App 异步通知事件流水表';
