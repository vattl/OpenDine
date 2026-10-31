-- 按下单时间范围查询订单对应的 openid，时间范围使用左闭右开区间。
SET @start_time = '2026-07-10 18:00:00';
SET @end_time   = '2026-07-11 02:00:00';
SET @shop_id    = 1;

-- 第一列名固定为 openid，可直接导出后上传到批量发券接口。
SELECT
    o.openid,
    COUNT(*) AS order_count,
    MIN(o.order_time) AS first_order_time,
    MAX(o.order_time) AS last_order_time,
    SUM(IFNULL(o.sett_amount, 0) - IFNULL(o.discount_amount, 0)
        + IFNULL(o.service_fee, 0) - IFNULL(o.refund_amount, 0)) AS consume_amount
FROM t_order o
WHERE o.order_time >= @start_time
  AND o.order_time < @end_time
  AND o.openid IS NOT NULL
  AND TRIM(o.openid) <> ''
  AND (@shop_id IS NULL OR o.shop_id = @shop_id)
GROUP BY o.openid
ORDER BY last_order_time DESC;

-- 明细级核对结果。
SELECT o.id AS order_id, o.order_no, o.shop_id, o.openid, o.order_time,
       o.dineInOrTakeOut, o.table_number, o.transac_status,
       o.sett_amount, o.service_fee, o.discount_amount, o.refund_amount
FROM t_order o
WHERE o.order_time >= @start_time
  AND o.order_time < @end_time
  AND o.openid IS NOT NULL
  AND TRIM(o.openid) <> ''
  AND (@shop_id IS NULL OR o.shop_id = @shop_id)
ORDER BY o.order_time DESC, o.id DESC;
