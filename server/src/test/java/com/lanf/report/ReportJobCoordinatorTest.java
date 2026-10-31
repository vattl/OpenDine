package com.lanf.report;

import com.lanf.common.ApiException;
import com.lanf.report.entity.ReportExportJob;
import com.lanf.report.service.ReportJobCoordinator;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static org.junit.jupiter.api.Assertions.*;

class ReportJobCoordinatorTest {
    JdbcTemplate jdbc;
    ReportJobCoordinator coordinator;
    @BeforeEach void setup() {
        DriverManagerDataSource ds = new DriverManagerDataSource("jdbc:h2:mem:report-" + System.nanoTime() + ";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "");
        jdbc = new JdbcTemplate(ds);
        jdbc.execute("CREATE TABLE t_report_job_admission(id INT PRIMARY KEY)");
        jdbc.update("INSERT INTO t_report_job_admission VALUES(1)");
        jdbc.execute("CREATE TABLE t_report_export_job(id BIGINT AUTO_INCREMENT PRIMARY KEY,shop_id INT,job_type VARCHAR(32),status VARCHAR(16),run_token VARCHAR(32),lease_until TIMESTAMP,updated_at TIMESTAMP,file_name VARCHAR(255),download_token VARCHAR(32),token_expires_at TIMESTAMP,result_summary_json TEXT,error VARCHAR(512))");
        coordinator = new ReportJobCoordinator(jdbc, new DataSourceTransactionManager(ds));
    }
    @AfterEach void cleanup() { coordinator.shutdown(); jdbc.execute("SET DB_CLOSE_DELAY 0"); }
    void insert(int shop) { coordinator.admit(shop, () -> jdbc.update("INSERT INTO t_report_export_job(shop_id,job_type,status) VALUES(?,'REPORT_EXPORT','PENDING')",shop)); }
    ReportExportJob job(long id) { ReportExportJob j=new ReportExportJob(); j.setId(id); j.setStatus("DONE"); return j; }

    @Test void perShopQuotaDoesNotBlockAnotherShopAndCloseRejectsAdmission() {
        for (int i=0;i<4;i++) insert(1);
        assertThrows(ApiException.class, () -> insert(1));
        insert(2);
        assertEquals(5,jdbc.queryForObject("SELECT COUNT(*) FROM t_report_export_job",Integer.class));
        coordinator.shutdown();
        assertThrows(ApiException.class, () -> insert(3));
    }
    @Test void expiredClaimCanBeRecoveredAndOldOwnerCannotFinish() {
        insert(1);
        ReportExportJob old=job(1), replacement=job(1);
        assertTrue(coordinator.claim(old));
        assertFalse(coordinator.claim(replacement));
        jdbc.update("UPDATE t_report_export_job SET lease_until=TIMESTAMP '2000-01-01 00:00:00'");
        assertTrue(coordinator.recoverable("REPORT_EXPORT").contains(1L));
        assertTrue(coordinator.claim(replacement));
        old.setStatus("DONE"); replacement.setStatus("DONE");
        old.setFile_name("old-attempt.csv"); replacement.setFile_name("replacement.csv");
        assertFalse(coordinator.finish(old));
        assertTrue(coordinator.finish(replacement));
        assertEquals("DONE",jdbc.queryForObject("SELECT status FROM t_report_export_job WHERE id=1",String.class));
        assertFalse(coordinator.finish(old));
        assertEquals("replacement.csv",jdbc.queryForObject("SELECT file_name FROM t_report_export_job WHERE id=1",String.class));
    }

    @Test void concurrentAdmissionsCannotExceedShopQuota() throws Exception {
        java.util.concurrent.ExecutorService callers=java.util.concurrent.Executors.newFixedThreadPool(8);
        try {
            java.util.List<java.util.concurrent.Future<Boolean>> results=new java.util.ArrayList<>();
            for(int i=0;i<8;i++) results.add(callers.submit(() -> {
                try { insert(1); return true; } catch(ApiException full) { return false; }
            }));
            int accepted=0;
            for(java.util.concurrent.Future<Boolean> result:results) if(result.get(5,java.util.concurrent.TimeUnit.SECONDS)) accepted++;
            assertEquals(4,accepted);
            assertEquals(4,jdbc.queryForObject("SELECT COUNT(*) FROM t_report_export_job",Integer.class));
        } finally { callers.shutdownNow(); }
    }

    @Test void globalQuotaBoundsPersistentBacklogAndCompletedJobFreesSlot() {
        for(int shop=1;shop<=32;shop++) for(int i=0;i<4;i++) insert(shop);
        assertThrows(ApiException.class,()->insert(33));
        jdbc.update("UPDATE t_report_export_job SET status='DONE' WHERE id=1");
        insert(33);
        assertEquals(128,jdbc.queryForObject("SELECT COUNT(*) FROM t_report_export_job WHERE status='PENDING'",Integer.class));
    }

    @Test void lateFinishIsAllowedIfNoOtherWorkerHasTakenOver() {
        insert(1);
        ReportExportJob current=job(1);
        assertTrue(coordinator.claim(current));
        jdbc.update("UPDATE t_report_export_job SET lease_until=TIMESTAMP '2000-01-01 00:00:00'");
        current.setStatus("DONE");
        assertTrue(coordinator.finish(current));
        assertFalse(coordinator.claim(job(1)));
    }

    @Test void startupRequiresMigrationAndOnlyReadsSchema() {
        JdbcTemplate checks=org.mockito.Mockito.mock(JdbcTemplate.class);
        ReportJobCoordinator guard=new ReportJobCoordinator(checks,new DataSourceTransactionManager(jdbc.getDataSource()));
        org.springframework.test.util.ReflectionTestUtils.setField(guard,"schedulingEnabled",false);
        try {
            assertThrows(IllegalStateException.class,()->guard.run(null));
            org.mockito.Mockito.when(checks.queryForObject(org.mockito.ArgumentMatchers.anyString(),org.mockito.ArgumentMatchers.eq(Integer.class))).thenReturn(1);
            org.mockito.Mockito.when(checks.queryForObject(org.mockito.ArgumentMatchers.anyString(),org.mockito.ArgumentMatchers.eq(String.class),org.mockito.ArgumentMatchers.anyString())).thenReturn("InnoDB");
            assertThrows(IllegalStateException.class,()->guard.run(null));
            org.mockito.Mockito.when(checks.queryForObject(org.mockito.ArgumentMatchers.anyString(),org.mockito.ArgumentMatchers.eq(Integer.class),org.mockito.ArgumentMatchers.anyString())).thenReturn(1);
            assertDoesNotThrow(()->guard.run(null));
            org.mockito.Mockito.verify(checks,org.mockito.Mockito.never()).execute(org.mockito.ArgumentMatchers.anyString());
        } finally {guard.shutdown();}
    }
}
