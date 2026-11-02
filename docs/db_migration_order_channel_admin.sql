-- ============================================================
-- t_order 新增：下单渠道 + 下单管理员ID（D010）
-- 目标：支撑按管理员维度的个人业绩订单统计与渠道营收归因
-- MySQL 8.0+；守护式加列（列已存在时跳过），可重复执行。
-- 执行一次即可；全新环境直接用 docs/db_diancan.sql 建表（已含两列）。
-- ============================================================
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS `p_order_add_channel_admin_columns`;
DELIMITER $$
CREATE PROCEDURE `p_order_add_channel_admin_columns`()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_order'
                     AND COLUMN_NAME = 'order_channel') THEN
        ALTER TABLE `t_order`
            ADD COLUMN `order_channel` varchar(20) DEFAULT NULL
            COMMENT '下单渠道（服务端写入，不采信客户端）：mini_program=C端小程序 / cashier=收银台 / takeout=小程序外卖 / ai=AI助手' AFTER `shop_id`;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_order'
                     AND COLUMN_NAME = 'order_admin_id') THEN
        ALTER TABLE `t_order`
            ADD COLUMN `order_admin_id` int(11) DEFAULT NULL
            COMMENT '下单管理员ID（B端JWT解析，收银/后台开单记录操作人；C端/AI为NULL），关联 t_admin.id' AFTER `order_channel`;
    END IF;
END$$
DELIMITER ;

CALL `p_order_add_channel_admin_columns`();
DROP PROCEDURE IF EXISTS `p_order_add_channel_admin_columns`;

-- ------------------------------------------------------------
-- 可选：历史数据回填（按需取消注释执行；默认不执行以保留真实可追溯性）
-- ① 历史收银单：openid 为收银占位常量（如 cashier_openid）→ cashier
--    UPDATE t_order SET order_channel = 'cashier'
--    WHERE order_channel IS NULL AND openid IN ('cashier_openid', 'cashier');
-- ② 历史外卖单：dineInOrTakeOut='外卖' → takeout
--    UPDATE t_order SET order_channel = 'takeout'
--    WHERE order_channel IS NULL AND dineInOrTakeOut = '外卖';
-- ③ 其余历史单保持 NULL（无法可靠判定渠道），不阻塞后续使用
-- ------------------------------------------------------------
