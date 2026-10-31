package com.lanf.kds.delivery;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import javax.annotation.PreDestroy;
import java.sql.Timestamp;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.*;

/** Source orders remain the recovery record; requests only enqueue bounded shop wakeups. */
@Component
public class CashierKdsBootstrapRepair {
    private static final org.slf4j.Logger log=org.slf4j.LoggerFactory.getLogger(CashierKdsBootstrapRepair.class);
    private final JdbcTemplate jdbc;
    private final CashierKdsProjectionService projection;
    private final TransactionTemplate transaction;
    private final Set<Integer> scheduled=ConcurrentHashMap.newKeySet();
    private final ExecutorService worker=new ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<>(16), task -> { Thread t=new Thread(task,"kds-bootstrap-repair"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    public CashierKdsBootstrapRepair(JdbcTemplate jdbc, CashierKdsProjectionService projection,
                                     PlatformTransactionManager manager) {
        this.jdbc=new JdbcTemplate(jdbc.getDataSource()); this.jdbc.setQueryTimeout(5);
        this.projection=projection; this.transaction=new TransactionTemplate(manager);
        this.transaction.setTimeout(5);
    }
    private List<Integer> missing(int shop, int limit) {
        return jdbc.queryForList("SELECT o.id FROM t_order o LEFT JOIN t_kds_order_projection p ON p.order_id=o.id "
                + "WHERE o.shop_id=? AND o.order_time>=? AND o.order_receiving='rec_order' "
                + "AND (o.transac_status IS NULL OR o.transac_status!='cancelled') "
                + "AND p.order_id IS NULL ORDER BY o.id LIMIT ?",Integer.class,
                shop,new Timestamp(System.currentTimeMillis()-2*86400000L),limit);
    }
    public void ensureReady(int shop) {
        if (missing(shop,1).isEmpty()) return;
        requestRepair(shop);
        throw new CashierKdsDeliveryException(503,5030,"BOOTSTRAP_PROJECTION_PENDING：投影恢复中，请续租并稍后重试首屏");
    }
    void requestRepair(int shop) {
        if (!scheduled.add(shop)) return;
        try {
            worker.execute(() -> {
                try { repairBatch(shop); }
                catch (Exception ex) { log.warn("bootstrap repair shop={} failed: {}",shop,ex.getClass().getSimpleName()); }
                finally { scheduled.remove(shop); }
            });
        } catch (RejectedExecutionException ex) { scheduled.remove(shop); }
    }
    void repairBatch(int shop) {
        for (Integer order : missing(shop,32)) {
            if (worker.isShutdown() || Thread.currentThread().isInterrupted()) return;
            try {
                List<Map<String,Object>> rows=jdbc.queryForList(
                        "SELECT order_receiving,transac_status FROM t_order WHERE id=?",order);
                if (rows.isEmpty()) {
                    jdbc.update("INSERT IGNORE INTO t_kds_order_projection (order_id,shop_id,projection_version,state,source_channel,payload_json,payload_hash) VALUES (?,?,0,'VOIDED','UNKNOWN','{}','0000000000000000000000000000000000000000000000000000000000000000')", order, shop);
                    continue;
                }
                Map<String,Object> r=rows.get(0);
                String eventType=resolveRepairEventType(
                        String.valueOf(r.get("order_receiving")),
                        r.get("transac_status")==null?null:String.valueOf(r.get("transac_status")));
                if (eventType==null) {
                    jdbc.update("INSERT IGNORE INTO t_kds_order_projection (order_id,shop_id,projection_version,state,source_channel,payload_json,payload_hash) VALUES (?,?,0,'VOIDED','UNKNOWN','{}','0000000000000000000000000000000000000000000000000000000000000000')", order, shop);
                    continue;
                }
                Long cursor = transaction.execute(status -> projection.publish(order,eventType,null,null,null));
                if (cursor == null) {
                    jdbc.update("INSERT IGNORE INTO t_kds_order_projection (order_id,shop_id,projection_version,state,source_channel,payload_json,payload_hash) VALUES (?,?,0,'VOIDED','UNKNOWN','{}','0000000000000000000000000000000000000000000000000000000000000000')", order, shop);
                }
            } catch (Exception ex) {
                log.warn("bootstrap repair order={} failed: {}",order,ex.getClass().getSimpleName());
                try {
                    jdbc.update("INSERT IGNORE INTO t_kds_order_projection (order_id,shop_id,projection_version,state,source_channel,payload_json,payload_hash) VALUES (?,?,0,'VOIDED','UNKNOWN','{}','0000000000000000000000000000000000000000000000000000000000000000')", order, shop);
                } catch (Exception ignored) {}
            }
        }
    }

    /** 补投事件按订单最新状态选择：取消单跳过，已收盘补 ORDER_CLOSED，其余补 ORDER_ACCEPTED。 */
    static String resolveRepairEventType(String acceptance,String transacStatus) {
        if ("cancelled".equals(acceptance) || "cancelled".equals(transacStatus)) return null;
        return "off_order".equals(acceptance)?"ORDER_CLOSED":"ORDER_ACCEPTED";
    }
    @PreDestroy public void close() { worker.shutdownNow(); }
}
