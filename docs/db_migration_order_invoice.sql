-- -------------------------------------------------------------
-- 电子发票开具申请与开票生命周期记录表
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `t_order_invoice` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `order_no` varchar(64) NOT NULL COMMENT '订单号',
  `shop_id` int(11) NOT NULL DEFAULT '1' COMMENT '门店ID',
  `fapiao_apply_id` varchar(64) NOT NULL COMMENT '发票申请单号（唯一标识一次开票申请）',
  `invoice_status` varchar(32) NOT NULL DEFAULT 'PENDING_SCAN' COMMENT '开票状态: PENDING_SCAN-待扫码填抬头, TITLE_SUBMITTED-抬头已提交, ISSUING-开票中, SUCCESS-开票成功, FAILED-开票失败, REVERSED-已冲红',
  `invoice_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '申请开票金额(元)',
  `tax_rate` decimal(5,4) NOT NULL DEFAULT '0.0600' COMMENT '税率，默认0.06',
  `invoice_qr_url` varchar(512) DEFAULT NULL COMMENT '顾客开票二维码链接',
  `buyer_title` varchar(128) DEFAULT NULL COMMENT '购方抬头名称（企业或个人）',
  `buyer_tax_no` varchar(64) DEFAULT NULL COMMENT '购方税号/纳税人识别号',
  `buyer_phone` varchar(32) DEFAULT NULL COMMENT '购方手机号',
  `buyer_email` varchar(128) DEFAULT NULL COMMENT '购方接收发票邮箱',
  `fapiao_number` varchar(64) DEFAULT NULL COMMENT '发票号码',
  `fapiao_code` varchar(64) DEFAULT NULL COMMENT '发票代码',
  `fapiao_file_url` varchar(512) DEFAULT NULL COMMENT '电子发票PDF/OFD文件下载链接',
  `operator_id` int(11) DEFAULT NULL COMMENT '触发开票的收银员/操作人ID',
  `error_msg` varchar(255) DEFAULT NULL COMMENT '开票失败原因',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fapiao_apply_id` (`fapiao_apply_id`),
  KEY `idx_order_no` (`order_no`),
  KEY `idx_shop_status` (`shop_id`, `invoice_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单电子发票开具申请表';
