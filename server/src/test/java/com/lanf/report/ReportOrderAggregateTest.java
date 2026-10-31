package com.lanf.report;

import com.lanf.report.service.ReportOrderAggregate;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class ReportOrderAggregateTest {
    JdbcTemplate jdbc;
    ReportOrderAggregate aggregate;
    final String start = "2025-01-01 16:00:00", end = "2025-01-02 04:00:00";
    @BeforeEach void setup() {
        DriverManagerDataSource ds = new DriverManagerDataSource("jdbc:h2:mem:aggregate-"+System.nanoTime()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        jdbc = new JdbcTemplate(ds); aggregate = new ReportOrderAggregate(ds);
        jdbc.execute("CREATE TABLE t_order(shop_id INT,merchantId VARCHAR(20),transac_status VARCHAR(20),order_receiving VARCHAR(20),order_time TIMESTAMP,pay_time TIMESTAMP,sett_amount DECIMAL(12,2),service_fee DECIMAL(12,2),discount_amount DECIMAL(12,2),refund_amount DECIMAL(12,2),pay_amount_gift DECIMAL(12,2))");
        jdbc.execute("CREATE TABLE t_receivable_ledger(shop_id INT,merchant_id VARCHAR(20),entry_type VARCHAR(20),amount_fen BIGINT,occurred_at TIMESTAMP)");
    }
    @AfterEach void cleanup() { jdbc.execute("SET DB_CLOSE_DELAY 0"); }
    void insert(int shop, String merchantId, String status, String receiving, String orderTime, String payTime,
                Double sett, Double fee, Double discount, Double refund, Double gift) {
        jdbc.update("INSERT INTO t_order VALUES(?,?,?,?,?,?,?,?,?,?,?)", shop, merchantId, status, receiving,
                orderTime, payTime, sett, fee, discount, refund, gift);
    }

    @Test void usesFinancialTimeExclusiveEndFallbackAndShopScope() {
        insert(1,"1","success","rec_order","2024-12-31 10:00:00",start,100d,5d,10d,3d,1d);
        insert(1,"1","success","off_order",start,end,80d,4d,null,2d,0d);
        insert(1,"1","success",null,start,null,null,null,null,null,null);
        insert(1,"1","success","rec_order",start,"2025-01-02 04:00:00.001",900d,0d,0d,0d,0d);
        insert(2,"1","success","rec_order",start,start,900d,0d,0d,0d,0d);
        insert(1,"2","success","rec_order",start,start,900d,0d,0d,0d,0d);
        insert(1,"pending","success","rec_order",start,start,900d,0d,0d,0d,0d);
        insert(1,"1","pending","rec_order",start,start,900d,0d,0d,0d,0d);
        insert(1,"1","success","unreceived",start,start,900d,0d,0d,0d,0d);
        insert(1,"1","success","rec_order","2025-01-01 15:59:59",null,900d,0d,0d,0d,0d);

        jdbc.update("INSERT INTO t_receivable_ledger VALUES(?,?,?,?,?)", 1, "1", "CHARGE", 10000L, start);
        jdbc.update("INSERT INTO t_receivable_ledger VALUES(?,?,?,?,?)", 1, "1", "COLLECTION", -4000L, start);
        jdbc.update("INSERT INTO t_receivable_ledger VALUES(?,?,?,?,?)", 1, "1", "WRITE_OFF", -500L, start);
        jdbc.update("INSERT INTO t_receivable_ledger VALUES(?,?,?,?,?)", 1, "1", "REVERSAL", -1000L, start);
        jdbc.update("INSERT INTO t_receivable_ledger VALUES(?,?,?,?,?)", 2, "1", "CHARGE", 99900L, start);

        assertEquals(Arrays.asList("day","2","95.00","91.00","10.00","5.00","3.00",
                        "100.00", "40.00", "5.00", "10.00"),
                aggregate.row(1,"day",start,end));
        assertEquals(Arrays.asList("day","0","0.00","0.00","0.00","0.00","0.00",
                "0.00", "0.00", "0.00", "0.00"),aggregate.row(3,"day",start,end));
        assertEquals("995.00",aggregate.row(null,"all",start,end).get(2));
    }
    @Test void decimalAggregateMatchesLegacyFinancialOutputAcrossManyOrders() {
        Random random = new Random(41);
        double total=0,netTotal=0,feeTotal=0,discountTotal=0,refundTotal=0;
        List<Object[]> batch=new ArrayList<>();
        for (int i=0;i<10000;i++) {
            double sett=random.nextInt(10000)/100.0, fee=random.nextInt(100)/100.0;
            double discount=random.nextInt(10000)/100.0, refund=random.nextInt(200)/100.0;
            double gift=random.nextInt(100)/100.0;
            batch.add(new Object[]{1,"1","success","rec_order",start,start,sett,fee,discount,refund,gift});
            total+=sett+fee-discount; netTotal+=sett+fee-discount-refund-gift; feeTotal+=fee; discountTotal+=discount; refundTotal+=refund;
        }
        jdbc.batchUpdate("INSERT INTO t_order VALUES(?,?,?,?,?,?,?,?,?,?,?)",batch);
        assertEquals(Arrays.asList("day","10000",legacy(total),legacy(netTotal),legacy(discountTotal),legacy(feeTotal),legacy(refundTotal),
                "0.00", "0.00", "0.00", "0.00"),aggregate.row(1,"day",start,end));
    }
    private String legacy(double value) { return String.format(Locale.ROOT,"%.2f",Math.round(value*100)/100.0); }

    @Test void queryTimeoutClosesStatementAndConnection() throws Exception {
        javax.sql.DataSource ds=org.mockito.Mockito.mock(javax.sql.DataSource.class);
        java.sql.Connection connection=org.mockito.Mockito.mock(java.sql.Connection.class);
        java.sql.PreparedStatement statement=org.mockito.Mockito.mock(java.sql.PreparedStatement.class);
        org.mockito.Mockito.when(ds.getConnection()).thenReturn(connection);
        org.mockito.Mockito.when(connection.prepareStatement(org.mockito.ArgumentMatchers.anyString())).thenReturn(statement);
        org.mockito.Mockito.when(statement.executeQuery()).thenThrow(new java.sql.SQLTimeoutException("query budget exhausted"));
        assertThrows(org.springframework.dao.DataAccessException.class,()->new ReportOrderAggregate(ds).row(1,"day",start,end));
        org.mockito.Mockito.verify(statement).setQueryTimeout(ReportOrderAggregate.QUERY_TIMEOUT_SECONDS);
        org.mockito.Mockito.verify(statement).close();
        org.mockito.Mockito.verify(connection,org.mockito.Mockito.atLeastOnce()).close();
    }
}
