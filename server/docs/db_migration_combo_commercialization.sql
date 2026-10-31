-- 菜品套餐商业化运营（限购、时段、用餐方式、叠券控制、配额）增量迁移脚本
-- 遵循增量无损演化原则，各字段均提供安全默认值。

SET NAMES utf8mb4;

CALL `p_add_col_if_missing`('t_combo', 'limit_per_order', '`limit_per_order` int NULL DEFAULT NULL COMMENT \'单笔订单限购份数，NULL或<=0表示不限\' AFTER `status`');
CALL `p_add_col_if_missing`('t_combo', 'limit_per_user', '`limit_per_user` int NULL DEFAULT NULL COMMENT \'单用户限购份数，NULL或<=0表示不限\' AFTER `limit_per_order`');
CALL `p_add_col_if_missing`('t_combo', 'limit_cycle', '`limit_cycle` varchar(20) NOT NULL DEFAULT \'daily\' COMMENT \'用户限购周期：daily(每日)|lifetime(终生)\' AFTER `limit_per_user`');
CALL `p_add_col_if_missing`('t_combo', 'start_time', '`start_time` datetime NULL DEFAULT NULL COMMENT \'活动生效开始时间，NULL表示不限\' AFTER `limit_cycle`');
CALL `p_add_col_if_missing`('t_combo', 'end_time', '`end_time` datetime NULL DEFAULT NULL COMMENT \'活动生效截止时间，NULL表示不限\' AFTER `start_time`');
CALL `p_add_col_if_missing`('t_combo', 'available_days', '`available_days` varchar(32) NULL DEFAULT NULL COMMENT \'可用星期，逗号分隔，如 1,2,3,4,5 代表周一至周五，NULL表示不限\' AFTER `end_time`');
CALL `p_add_col_if_missing`('t_combo', 'time_range_start', '`time_range_start` varchar(16) NULL DEFAULT NULL COMMENT \'每日可用起始时间段，如 11:00\' AFTER `available_days`');
CALL `p_add_col_if_missing`('t_combo', 'time_range_end', '`time_range_end` varchar(16) NULL DEFAULT NULL COMMENT \'每日可用截止时间段，如 14:00\' AFTER `time_range_start`');
CALL `p_add_col_if_missing`('t_combo', 'apply_dining_type', '`apply_dining_type` varchar(20) NOT NULL DEFAULT \'all\' COMMENT \'适用就餐方式：all(全部)|dine_in(仅限堂食)|take_out(仅限外卖打包)\' AFTER `time_range_end`');
CALL `p_add_col_if_missing`('t_combo', 'allow_coupon', '`allow_coupon` tinyint NOT NULL DEFAULT 1 COMMENT \'是否允许叠加优惠券：1允许 0禁止\' AFTER `apply_dining_type`');
CALL `p_add_col_if_missing`('t_combo', 'daily_stock', '`daily_stock` int NULL DEFAULT NULL COMMENT \'每日套餐配额，NULL表示不限\' AFTER `allow_coupon`');
