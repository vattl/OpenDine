package com.lanf.report.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import javax.sql.DataSource;
import java.util.Arrays;
import java.util.List;
import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * 营业报表订单聚合。
 *
 * <p>财务归属优先使用 {@code pay_time}；仅兼容历史成功订单的空支付时间时回退
 * {@code order_time}。时间窗口统一为左闭右开区间，避免切日点重复计入相邻营业日。</p>
 */
@Repository
public class ReportOrderAggregate {
    /** Bounds a 92-day daily export below its 30-minute execution lease. */
    public static final int QUERY_TIMEOUT_SECONDS = 5;
    private final JdbcTemplate jdbc;

    public ReportOrderAggregate(DataSource dataSource) {
        jdbc = new JdbcTemplate(dataSource);
        jdbc.setQueryTimeout(QUERY_TIMEOUT_SECONDS); // applies only to these export statements
    }

    public List<String> row(Integer shopId, String label, String start, String end) {
        String orderSql = "SELECT COUNT(*) AS orders, "
                + "COALESCE(SUM(COALESCE(sett_amount,0)+COALESCE(service_fee,0)-COALESCE(discount_amount,0)),0) AS total, "
                + "COALESCE(SUM(COALESCE(sett_amount,0)+COALESCE(service_fee,0)-COALESCE(discount_amount,0)-COALESCE(refund_amount,0)-COALESCE(pay_amount_gift,0)),0) AS net, "
                + "COALESCE(SUM(discount_amount),0) AS discount, "
                + "COALESCE(SUM(service_fee),0) AS fee, COALESCE(SUM(refund_amount),0) AS refund "
                + "FROM t_order WHERE merchantId='1' AND transac_status='success' "
                + "AND (order_receiving IN ('rec_order','off_order') OR order_receiving IS NULL) "
                + "AND ((pay_time IS NOT NULL AND pay_time>=? AND pay_time<?) "
                + "OR (pay_time IS NULL AND order_time>=? AND order_time<?))";
        if (shopId != null) orderSql += " AND shop_id=?";
        String receivableSql = "SELECT "
                + "COALESCE(SUM(CASE WHEN entry_type='CHARGE' THEN amount_fen ELSE 0 END),0) charged_fen, "
                + "COALESCE(-SUM(CASE WHEN entry_type='COLLECTION' THEN amount_fen ELSE 0 END),0) collected_fen, "
                + "COALESCE(-SUM(CASE WHEN entry_type='WRITE_OFF' THEN amount_fen ELSE 0 END),0) writeoff_fen, "
                + "COALESCE(-SUM(CASE WHEN entry_type='REVERSAL' THEN amount_fen ELSE 0 END),0) reversed_fen "
                + "FROM t_receivable_ledger WHERE merchant_id='1' AND occurred_at>=? AND occurred_at<?";
        if (shopId != null) receivableSql += " AND shop_id=?";
        String sql = "SELECT o.*, r.* FROM (" + orderSql + ") o CROSS JOIN (" + receivableSql + ") r";
        Object[] args = shopId == null
                ? new Object[]{start, end, start, end, start, end}
                : new Object[]{start, end, start, end, shopId, start, end, shopId};
        return jdbc.queryForObject(sql, (rs, index) -> Arrays.asList(label,
                Long.toString(rs.getLong("orders")), money(rs.getBigDecimal("total")),
                money(rs.getBigDecimal("net")),
                money(rs.getBigDecimal("discount")), money(rs.getBigDecimal("fee")), money(rs.getBigDecimal("refund")),
                fenMoney(rs.getBigDecimal("charged_fen")), fenMoney(rs.getBigDecimal("collected_fen")),
                fenMoney(rs.getBigDecimal("writeoff_fen")), fenMoney(rs.getBigDecimal("reversed_fen"))), args);
    }

    private static String fenMoney(BigDecimal value) {
        return money(value.movePointLeft(2));
    }

    private static String money(BigDecimal value) {
        return value.setScale(2, RoundingMode.HALF_UP).toPlainString();
    }
}
