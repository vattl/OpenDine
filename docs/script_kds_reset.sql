-- KDS 运行时数据重置：清空厨显工单与流转状态，保留档口/绑屏/门店配置/设备
-- 不修改 t_order / t_order_detail。
--
-- 清空表：
--   t_kds_flow_batch   流转批次
--   t_kds_ticket       厨显工单
--   t_kds_order        整单厨显状态
--   t_kds_skewer_pick  抓串已抓记录
--   t_kds_sync_dedup   厨显离线同步幂等键（可选，见下方注释）
--
-- 保留表：
--   t_kds_station, t_kds_station_category, t_kds_dish_screen,
--   t_kds_shop_config, t_kds_device
--
-- 用法：
--   1) 全门店清空：直接执行「方案 A」
--   2) 单门店清空：设置 @shop_id 后执行「方案 B」
--   3) 推荐：python server/scripts/kds_reset.py --dry-run / --yes
--
-- 执行前请备份。清空后厨显屏需刷新；未支付订单如需重新进厨显可调用 POST /admin/kds/ticket/repush。

-- =============================================================================
-- 方案 A：全门店清空（TRUNCATE，自增 id 归零）
-- =============================================================================
START TRANSACTION;
TRUNCATE TABLE `t_kds_flow_batch`;
TRUNCATE TABLE `t_kds_ticket`;
TRUNCATE TABLE `t_kds_order`;
TRUNCATE TABLE `t_kds_skewer_pick`;
TRUNCATE TABLE `t_kds_sync_dedup`;
COMMIT;

-- =============================================================================
-- 方案 B：按门店清空（将 @shop_id 改为目标 t_shop.id，取消注释后执行）
-- =============================================================================
-- SET @shop_id = 1;
--
-- START TRANSACTION;
--
-- DELETE FROM `t_kds_flow_batch` WHERE `shop_id` = @shop_id;
-- DELETE FROM `t_kds_ticket` WHERE `shop_id` = @shop_id;
-- DELETE FROM `t_kds_order` WHERE `shop_id` = @shop_id;
-- DELETE FROM `t_kds_skewer_pick` WHERE `shop_id` = @shop_id;
-- DELETE FROM `t_kds_sync_dedup` WHERE `shop_id` = @shop_id;
--
-- COMMIT;

-- 核对（应均为 0 或仅剩其它门店数据）
-- SELECT 'flow_batch' AS tbl, COUNT(*) AS cnt FROM t_kds_flow_batch WHERE shop_id = @shop_id
-- UNION ALL SELECT 'ticket', COUNT(*) FROM t_kds_ticket WHERE shop_id = @shop_id
-- UNION ALL SELECT 'kds_order', COUNT(*) FROM t_kds_order WHERE shop_id = @shop_id
-- UNION ALL SELECT 'skewer_pick', COUNT(*) FROM t_kds_skewer_pick WHERE shop_id = @shop_id
-- UNION ALL SELECT 'sync_dedup', COUNT(*) FROM t_kds_sync_dedup WHERE shop_id = @shop_id;
