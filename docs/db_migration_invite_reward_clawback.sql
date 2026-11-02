CREATE TABLE IF NOT EXISTS `t_invite_reward_clawback` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `invite_record_id` bigint NOT NULL,
  `inviter_user_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `outstanding_amount` decimal(12,2) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'PENDING',
  `attempts` int NOT NULL DEFAULT 0,
  `last_error` varchar(255) NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_invite_clawback_order` (`invite_record_id`, `order_no`),
  KEY `idx_invite_clawback_status` (`status`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='邀请首单返现退款冲正待收回队列';

UPDATE `t_invite_reward_clawback`
SET `outstanding_amount` = 0
WHERE `status` = 'COMPLETED' AND `outstanding_amount` <> 0;
