package com.lanf.report.service;

import com.lanf.common.ApiException;
import com.lanf.report.entity.ReportExportJob;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import javax.annotation.PreDestroy;
import java.util.*;
import java.util.concurrent.*;

@Component
public class ReportJobCoordinator implements ApplicationRunner {
    /** Export aggregation has a five-second statement budget for at most 92 daily rows. */
    static final int EXECUTION_LEASE_MINUTES = 30;
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(ReportJobCoordinator.class);
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final Map<String,Runnable> recoveries = new ConcurrentHashMap<>();
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r,"report-job-recovery"); t.setDaemon(true); return t;
    });
    @Value("${app.scheduling.enabled:true}") private boolean schedulingEnabled = true;
    private volatile boolean closed;

    public ReportJobCoordinator(JdbcTemplate jdbc, PlatformTransactionManager manager) {
        this.jdbc=jdbc; this.transaction=new TransactionTemplate(manager);
    }
    public void register(String type, Runnable recovery) { recoveries.put(type,recovery); }
    @Override public void run(ApplicationArguments args) {
        jdbc.queryForList("SELECT run_token,lease_until FROM t_report_export_job WHERE 1=0");
        Integer admissionRows=jdbc.queryForObject("SELECT COUNT(*) FROM t_report_job_admission WHERE id=1",Integer.class);
        if (admissionRows==null || admissionRows!=1)
            throw new IllegalStateException("Apply docs/db_migration_report_job_recovery.sql before startup");
        for (String table : Arrays.asList("t_report_export_job","t_report_job_admission")) {
            String engine=jdbc.queryForObject("SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?",String.class,table);
            if (!"InnoDB".equalsIgnoreCase(engine)) throw new IllegalStateException(table+" must use InnoDB for job recovery");
        }
        for (String index : Arrays.asList("idx_report_job_recovery","idx_report_job_shop_pending")) {
            Integer count=jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_report_export_job' AND INDEX_NAME=?",Integer.class,index);
            if (count==null || count==0) throw new IllegalStateException("Missing report recovery index "+index);
        }
        if (schedulingEnabled) timer.scheduleWithFixedDelay(() -> {
            for (Runnable recovery : recoveries.values()) {
                try { recovery.run(); }
                catch (Exception e) { log.warn("report recovery failed: {}",e.getClass().getSimpleName()); }
            }
        },5,5,TimeUnit.SECONDS);
    }
    public void admit(Integer shopId, Runnable insert) {
        if (closed) throw new ApiException(503,"REPORT_WORKER_CLOSED","任务服务正在停止");
        transaction.execute(s -> {
            jdbc.queryForObject("SELECT id FROM t_report_job_admission WHERE id=1 FOR UPDATE",Integer.class);
            String active=" FROM t_report_export_job WHERE job_type IN ('REPORT_EXPORT','ARCHIVE_SEARCH') AND status IN ('PENDING','RUNNING')";
            // Locking reads see current committed rows even when joining an existing repeatable-read transaction.
            List<Integer> shops=jdbc.queryForList("SELECT shop_id"+active+" ORDER BY id LIMIT 129 FOR UPDATE",Integer.class);
            long perShop=shops.stream().filter(shop -> Objects.equals(shop,shopId)).count();
            if (shops.size()>=128 || perShop>=4) throw new ApiException(429,"REPORT_JOB_QUOTA_EXCEEDED","未完成任务过多，请稍后重试");
            if (closed) throw new ApiException(503,"REPORT_WORKER_CLOSED","任务服务正在停止");
            insert.run(); return null;
        });
    }
    public boolean claim(ReportExportJob job) {
        if (closed) return false;
        String token=UUID.randomUUID().toString().replace("-","");
        int changed=jdbc.update("UPDATE t_report_export_job SET status='RUNNING',run_token=?,lease_until=TIMESTAMPADD(MINUTE," + EXECUTION_LEASE_MINUTES + ",CURRENT_TIMESTAMP),updated_at=CURRENT_TIMESTAMP WHERE id=? AND (status='PENDING' OR (status='RUNNING' AND (lease_until IS NULL OR lease_until<CURRENT_TIMESTAMP)))",token,job.getId());
        if (changed==0) return false;
        job.setRun_token(token); job.setStatus(ReportExportJob.STATUS_RUNNING);
        return true;
    }
    public boolean finish(ReportExportJob job) {
        if (job.getRun_token()==null) return false;
        if (!ReportExportJob.STATUS_DONE.equals(job.getStatus()) && !ReportExportJob.STATUS_FAILED.equals(job.getStatus()))
            throw new IllegalArgumentException("only terminal job states may be published");
        // Expiry permits takeover; the token changes only on successful takeover. An uncontested late finish is safe.
        return jdbc.update("UPDATE t_report_export_job SET status=?,file_name=?,download_token=?,token_expires_at=?,result_summary_json=?,error=?,updated_at=CURRENT_TIMESTAMP,lease_until=NULL WHERE id=? AND status='RUNNING' AND run_token=?",
                job.getStatus(),job.getFile_name(),job.getDownload_token(),job.getToken_expires_at(),job.getResult_summary_json(),job.getError(),job.getId(),job.getRun_token())==1;
    }
    public List<Long> recoverable(String type) {
        if (closed) return Collections.emptyList();
        return jdbc.queryForList("SELECT id FROM t_report_export_job WHERE job_type=? AND (status='PENDING' OR (status='RUNNING' AND (lease_until IS NULL OR lease_until<CURRENT_TIMESTAMP))) ORDER BY id LIMIT 32",Long.class,type);
    }
    @PreDestroy public void shutdown() { closed=true; timer.shutdownNow(); }
}
