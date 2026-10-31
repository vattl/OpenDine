-- 门店级独立结算时间：营业日数据统计窗口的结束时间（如 04:00）
-- 与 close_time（门店营业结束时间）独立，便于营业结束后留缓冲再结算
-- 营业日 D 的统计窗口 = [D 的 open_time, D+1 的 settle_time)
-- 为空时回退 close_time，再为空回退默认 04:00
ALTER TABLE t_shop
    ADD COLUMN settle_time VARCHAR(8) DEFAULT '04:00'
    COMMENT '每日结算截止时间(HH:mm)，营业日统计窗口=[open_time,次日settle_time)'
    AFTER close_time;
