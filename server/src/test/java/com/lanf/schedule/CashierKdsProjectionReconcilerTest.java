package com.lanf.schedule;

import com.lanf.kds.delivery.CashierKdsProjectionService;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class CashierKdsProjectionReconcilerTest {
    private JdbcTemplate jdbc;
    private CashierKdsProjectionReconciler reconciler;
    private CashierKdsProjectionService projection;
    @BeforeEach void setup() {
        DriverManagerDataSource ds = new DriverManagerDataSource("jdbc:h2:mem:t06-"+System.nanoTime()+";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "");
        jdbc = new JdbcTemplate(ds);
        jdbc.execute("CREATE TABLE t_order(id INT PRIMARY KEY,shop_id INT,order_time TIMESTAMP,order_receiving VARCHAR(20),transac_status VARCHAR(20))");
        jdbc.execute("CREATE TABLE t_kds_order_projection(order_id INT PRIMARY KEY)");
        for (int id=1;id<=40;id++) jdbc.update("INSERT INTO t_order VALUES(?,1,NOW(),'rec_order','unsettled')", id);
        projection=mock(CashierKdsProjectionService.class);
        reconciler=new CashierKdsProjectionReconciler(jdbc,projection);
        org.springframework.test.util.ReflectionTestUtils.setField(reconciler,"batchSize",32);
    }
    @AfterEach void close() { reconciler.close(); jdbc.execute("SET DB_CLOSE_DELAY 0"); }
    @Test void cursorCoversLargeRecoveryInBoundedBatchesBeforeWrapping() {
        assertEquals(40, jdbc.queryForObject("SELECT COUNT(*) FROM t_order WHERE order_time>=?", Integer.class,
                new java.sql.Timestamp(System.currentTimeMillis() - java.util.concurrent.TimeUnit.DAYS.toMillis(2))).intValue());
        reconciler.reconcile(); reconciler.reconcile();
        org.mockito.ArgumentCaptor<Integer> ids = org.mockito.ArgumentCaptor.forClass(Integer.class);
        verify(projection, times(40)).publish(ids.capture(), eq("ORDER_UPDATED"), isNull(), isNull(), isNull());
        Set<Integer> repaired = new HashSet<>(ids.getAllValues());
        assertEquals(40,repaired.size());
        reconciler.reconcile();
        verify(projection, times(72)).publish(anyInt(), eq("ORDER_UPDATED"), isNull(), isNull(), isNull());
    }

}
