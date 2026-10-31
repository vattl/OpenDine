-- 会员充值流水：微信 JSAPI 充值与后台人工充值（含赠送），供 C 端查询历史。
-- 执行前请备份数据库。
-- 已在运行的库（如 db_diancan）未建表时执行本脚本；全新库也可直接使用 docs/db_diancan.sql 中的同结构定义。

CREATE TABLE IF NOT EXISTS `t_member_recharge` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `user_id` INT NOT NULL COMMENT 't_user.id',
  `openid` VARCHAR(64) NOT NULL,
  `order_no` VARCHAR(64) DEFAULT NULL COMMENT '微信充值商户单号（与 t_order 无关）；后台渠道可为空',
  `shop_id` INT DEFAULT NULL,
  `operator_id` INT DEFAULT NULL COMMENT '后台人工充值操作员ID',
  `drawer_session_id` BIGINT DEFAULT NULL COMMENT '后台人工充值归属钱箱会话ID',
  `channel` VARCHAR(20) NOT NULL COMMENT 'wechat | admin',
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT 'pending|success|cancelled',
  `recharge_amount` DECIMAL(12,2) NOT NULL COMMENT '充值本金（元）',
  `gift_amount` DECIMAL(12,2) NOT NULL DEFAULT 0.00 COMMENT '赠送（元）',
  `total_amount` DECIMAL(12,2) NOT NULL COMMENT '入账合计（元）=本金+赠送',
  `transaction_id` VARCHAR(128) DEFAULT NULL,
  `pay_time` DATETIME DEFAULT NULL,
  `remark` VARCHAR(500) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_member_recharge_openid_created` (`openid`, `created_at`),
  KEY `idx_member_recharge_user_created` (`user_id`, `created_at`),
  KEY `idx_recharge_drawer_status` (`drawer_session_id`, `status`),
  KEY `idx_recharge_shop_status_pay_time` (`shop_id`, `status`, `pay_time`),
  UNIQUE KEY `uk_member_recharge_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会员充值流水';
