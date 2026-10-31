package com.lanf.report;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.adminlog.service.AdminLogService;
import com.lanf.adminlog.util.LogMaskUtil;
import com.lanf.common.ApiException;
import com.lanf.entity.OperationLog;
import com.lanf.report.entity.ReportExportJob;
import com.lanf.report.mapper.ReportExportJobMapper;
import com.lanf.report.service.ReportExportService;
import com.lanf.report.service.ReportOrderAggregate;
import com.lanf.service.IShopService;
import com.lanf.service.IOperationLogService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.AbstractExecutorService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 报表导出任务 + 日志查询/归档/导出 单元测试（纯 Mockito，不起 Spring 容器）。
 * 覆盖：导出任务 token 过期判断、报表任务异步状态机、日志 30 天窗口过滤、
 * 脱敏正则、归档 job 状态机（PENDING→DONE/FAILED）、purpose 必填。
 * 两个服务的执行器均替换为同步执行器，使异步流程确定性地内联完成。
 */
class ReportLogServiceTest {

    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final String EXPORT_DIR = "target/test-exports";

    private ReportExportService reportService;
    private AdminLogService logService;
    private ReportExportJobMapper jobMapper;
    private ReportOrderAggregate orderAggregate;
    private IShopService shopService;
    private IOperationLogService operationLogService;

    private final AtomicInteger seq = new AtomicInteger();
    private final AtomicReference<ReportExportJob> inserted = new AtomicReference<>();
    /** insert 调用瞬间的状态快照（提交异步之前，必为 PENDING） */
    private final AtomicReference<String> statusAtInsert = new AtomicReference<>();

    @Test void stoppedServicesRejectNewJobsBeforePersistence() {
        ExecutorService reportWorker=com.lanf.report.service.BoundedJobExecutor.create("test-stop-report");
        ExecutorService archiveWorker=com.lanf.report.service.BoundedJobExecutor.create("test-stop-archive");
        ReflectionTestUtils.setField(reportService,"exportExecutor",reportWorker);
        ReflectionTestUtils.setField(logService,"archiveExecutor",archiveWorker);
        reportService.shutdown(); logService.shutdown();
        assertEquals(503,assertThrows(ApiException.class,()->reportService.createReportExportJob(1,1,"daily",Collections.emptyMap(),"csv")).getHttpStatus());
        assertEquals(503,assertThrows(ApiException.class,()->logService.createArchiveSearch(1,1,Collections.emptyMap())).getHttpStatus());
        verify(jobMapper,never()).insert(any());
    }

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        jobMapper = mock(ReportExportJobMapper.class);
        orderAggregate = mock(ReportOrderAggregate.class);
        shopService = mock(IShopService.class);
        com.lanf.entity.Shop defaultShop = new com.lanf.entity.Shop();
        defaultShop.setId(1);
        defaultShop.setSettle_time("04:00");
        when(shopService.getById(any())).thenReturn(defaultShop);
        operationLogService = mock(IOperationLogService.class);

        when(jobMapper.insert(any(ReportExportJob.class))).thenAnswer(inv -> {
            ReportExportJob j = inv.getArgument(0);
            j.setId((long) seq.incrementAndGet());
            inserted.set(j);
            statusAtInsert.set(j.getStatus());
            return 1;
        });
        when(jobMapper.updateById(any(ReportExportJob.class))).thenReturn(1);
        com.lanf.report.service.ReportJobCoordinator coordinator = mock(com.lanf.report.service.ReportJobCoordinator.class);
        org.mockito.Mockito.doAnswer(call -> { ((Runnable) call.getArgument(1)).run(); return null; })
                .when(coordinator).admit(any(), any());
        when(coordinator.claim(any())).thenAnswer(call -> {
            ReportExportJob job = call.getArgument(0);
            job.setRun_token("test-run-token"); job.setStatus(ReportExportJob.STATUS_RUNNING); return true;
        });
        when(coordinator.finish(any())).thenReturn(true);

        reportService = new ReportExportService();
        ReflectionTestUtils.setField(reportService, "jobCoordinator", coordinator);
        ReflectionTestUtils.setField(reportService, "reportExportJobMapper", jobMapper);
        ReflectionTestUtils.setField(reportService, "orderAggregate", orderAggregate);
        ReflectionTestUtils.setField(reportService, "shopService", shopService);
        ReflectionTestUtils.setField(reportService, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(reportService, "exportDir", EXPORT_DIR);
        ReflectionTestUtils.setField(reportService, "exportExecutor", directExecutor());

        logService = new AdminLogService();
        ReflectionTestUtils.setField(logService, "jobCoordinator", coordinator);
        ReflectionTestUtils.setField(logService, "operationLogService", operationLogService);
        ReflectionTestUtils.setField(logService, "reportExportService", reportService);
        ReflectionTestUtils.setField(logService, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(logService, "exportDir", EXPORT_DIR);
        ReflectionTestUtils.setField(logService, "archiveExecutor", directExecutor());
    }

    /** 同步执行器：execute 即 run，使异步任务内联完成，测试可断言终态 */
    private static ExecutorService directExecutor() {
        return new AbstractExecutorService() {
            private boolean stopped;
            @Override
            public void execute(Runnable command) {
                command.run();
            }

            @Override
            public void shutdown() {
                stopped = true;
            }

            @Override
            public List<Runnable> shutdownNow() {
                stopped = true;
                return Collections.emptyList();
            }

            @Override
            public boolean isShutdown() {
                return stopped;
            }

            @Override
            public boolean isTerminated() {
                return stopped;
            }

            @Override
            public boolean awaitTermination(long timeout, TimeUnit unit) {
                return true;
            }
        };
    }

    private static OperationLog logRow(String snapshot) {
        OperationLog row = new OperationLog();
        row.setId(99L);
        row.setShop_id(1);
        row.setModule("settings");
        row.setAction("save_store");
        row.setAdmin_id(5);
        row.setResult_status("SUCCESS");
        row.setRequest_snapshot(snapshot);
        row.setReason("回访电话13812345678");
        row.setCreated_at(new Date());
        return row;
    }

    // ---------------- 1) 报表导出任务：创建 + 异步生成 + token ----------------

    @Test
    @SuppressWarnings("unchecked")
    void interruptedShutdownKeepsBothKindsRecoverableInsteadOfFailed() {
        when(orderAggregate.row(any(), any(), any(), any())).thenAnswer(call -> {
            reportService.shutdown(); throw new IllegalStateException("shutdown interrupted query");
        });
        reportService.createReportExportJob(1,5,"daily",single("date","2025-01-01"),"csv");
        assertEquals("RUNNING",inserted.get().getStatus());
        when(operationLogService.count(any(Wrapper.class))).thenAnswer(call -> {
            logService.shutdown(); throw new IllegalStateException("shutdown interrupted query");
        });
        logService.createArchiveSearch(1,5,Collections.emptyMap());
        assertEquals("RUNNING",inserted.get().getStatus());
    }

    @Test
    @SuppressWarnings("unchecked")
    void reportJobCreatesPendingThenGeneratesCsvWithToken() throws Exception {
        when(orderAggregate.row(any(), any(), any(), any()))
                .thenAnswer(call -> Arrays.asList(call.getArgument(1), "2", "179.00", "169.00", "10.00", "9.00", "0.00",
                        "50.00", "20.00", "3.00", "5.00"));
        String yesterday = LocalDate.now(ZONE).minusDays(1).toString();
        Map<String, Object> filters = new LinkedHashMap<>();
        filters.put("date", yesterday);

        Map<String, Object> resp = reportService.createReportExportJob(1, 5, "daily", filters, "csv");

        assertEquals(1L, resp.get("jobId"));
        assertEquals("PENDING", resp.get("status"), "响应契约恒为创建时状态 PENDING");
        assertEquals("PENDING", statusAtInsert.get(), "落库时状态必须为 PENDING");

        ReportExportJob job = inserted.get();
        assertEquals("DONE", job.getStatus(), "同步执行器下任务应内联完成");
        assertEquals(ReportExportJob.TYPE_REPORT_EXPORT, job.getJob_type());
        assertNotNull(job.getDownload_token());
        assertTrue(job.getDownload_token().matches("[0-9a-f]{32}"), "token 必须是 32 位随机十六进制");
        assertTrue(job.getToken_expires_at().isAfter(LocalDateTime.now(ZONE)), "token 有效期应为 now+15min");
        assertNotNull(job.getFile_name());

        List<String> lines = Files.readAllLines(Paths.get(EXPORT_DIR, job.getFile_name()), StandardCharsets.UTF_8);
        String header = lines.get(0).replace("\uFEFF", "");
        assertEquals("business_date,order_count,total_amount,net_amount,discount_amount,service_fee,refund_amount,receivable_charged_amount,receivable_collected_amount,receivable_writeoff_amount,receivable_reversed_amount", header);
        boolean hasSummaryRow = lines.stream().anyMatch(l -> l.contains(yesterday + ",2,179.00,169.00,10.00,9.00,0.00"));
        assertTrue(hasSummaryRow, "净额应扣除退款和赠送金：实际=" + lines);
    }

    @Test
    @SuppressWarnings("unchecked")
    void reportJobFailureMarksFailedWithError() {
        when(orderAggregate.row(any(), any(), any(), any())).thenThrow(new RuntimeException("db down"));
        Map<String, Object> filters = new LinkedHashMap<>();
        filters.put("startDate", "2025-01-01");
        filters.put("endDate", "2025-01-07");

        Map<String, Object> resp = reportService.createReportExportJob(1, 5, "weekly", filters, "csv");

        assertEquals("PENDING", resp.get("status"));
        ReportExportJob job = inserted.get();
        assertEquals("FAILED", job.getStatus());
        assertNotNull(job.getError());
        assertTrue(job.getError().contains("db down"));
    }

    @Test
    void reportJobValidatesTypeFormatAndRange() {
        ApiException noType = assertThrows(ApiException.class,
                () -> reportService.createReportExportJob(1, 5, null, new LinkedHashMap<>(), "csv"));
        assertEquals(400, noType.getHttpStatus());
        assertEquals("REPORT_TYPE_REQUIRED", noType.getErrorCode());

        ApiException badType = assertThrows(ApiException.class,
                () -> reportService.createReportExportJob(1, 5, "yearly", new LinkedHashMap<>(), "csv"));
        assertEquals("REPORT_TYPE_INVALID", badType.getErrorCode());

        ApiException xlsx = assertThrows(ApiException.class,
                () -> reportService.createReportExportJob(1, 5, "daily", single("date", "2025-01-01"), "xlsx"));
        assertEquals(400, xlsx.getHttpStatus());
        assertEquals("REPORT_FORMAT_INVALID", xlsx.getErrorCode());

        ApiException noRange = assertThrows(ApiException.class,
                () -> reportService.createReportExportJob(1, 5, "daily", new LinkedHashMap<>(), "csv"));
        assertEquals("REPORT_RANGE_REQUIRED", noRange.getErrorCode());

        ApiException badRange = assertThrows(ApiException.class,
                () -> reportService.createReportExportJob(1, 5, "monthly", single("startDate", "2025-01-01"), "csv"));
        assertEquals("REPORT_RANGE_REQUIRED", badRange.getErrorCode());

        verify(jobMapper, never()).insert(any(ReportExportJob.class));
    }

    @Test
    void allReportTypesRejectReversedAndOverBudgetRangesBeforeInsertion() {
        for (String type : Arrays.asList("daily", "weekly", "monthly")) {
            for (String end : Arrays.asList("2024-12-31", "2025-04-03")) {
                Map<String,Object> filters = new LinkedHashMap<>();
                filters.put("startDate", "2025-01-01"); filters.put("endDate", end);
                ApiException error = assertThrows(ApiException.class,
                        () -> reportService.createReportExportJob(1,5,type,filters,"csv"));
                assertEquals("REPORT_RANGE_INVALID", error.getErrorCode());
            }
        }
        verify(jobMapper, never()).insert(any(ReportExportJob.class));
    }
    @Test
    void ninetyTwoDaysAreWrittenInOrderAndDailyDateTakesPrecedence() throws Exception {
        AtomicInteger queries = new AtomicInteger();
        when(orderAggregate.row(any(),any(),any(),any())).thenAnswer(call -> {
            queries.incrementAndGet();
            return Arrays.asList(call.getArgument(1), "0", "0.00", "0.00", "0.00", "0.00", "0.00");
        });
        Map<String,Object> filters = new LinkedHashMap<>();
        filters.put("date", "2024-01-01"); filters.put("startDate", "2023-01-01"); filters.put("endDate", "2024-04-01");
        reportService.createReportExportJob(1,5,"daily",filters,"csv");
        assertEquals("DONE", inserted.get().getStatus());
        List<String> lines = Files.readAllLines(Paths.get(EXPORT_DIR,inserted.get().getFile_name()),StandardCharsets.UTF_8);
        assertEquals(93, lines.size()); assertEquals(92, queries.get());
        assertTrue(lines.get(60).startsWith("2024-02-29,"));
        assertTrue(lines.get(92).startsWith("2024-04-01,"));
    }

    @Test
    void summaryUsesOneAggregateAndAppliesShopSettlementWindow() {
        when(orderAggregate.row(any(),any(),any(),any())).thenReturn(Arrays.asList("range","1","1.00","1.00","0.00","0.00","0.00"));
        Map<String,Object> filters = new LinkedHashMap<>();
        filters.put("startDate", "2025-01-01"); filters.put("endDate", "2025-04-02");
        reportService.createReportExportJob(7,5,"monthly",filters,"csv");
        assertEquals("DONE", inserted.get().getStatus());
        verify(orderAggregate).row(7,"2025-01-01~2025-04-02","2025-01-01 04:00:00","2025-04-03 04:00:00");
    }

    @Test
    void recoveringLegacyOversizedJobFailsBeforeQuery() {
        ReportExportJob job = new ReportExportJob();
        job.setId(99L); job.setShop_id(1); job.setReport_type("weekly");
        job.setFilters_json("{\"startDate\":\"2020-01-01\",\"endDate\":\"2025-01-01\"}");
        ReflectionTestUtils.invokeMethod(reportService,"runReportJob",job);
        assertEquals("FAILED",job.getStatus());
        verify(orderAggregate,never()).row(any(),any(),any(),any());
    }
    @Test
    void dailyUsesShopSettlementWindowAndClosesPartialFileOnQueryFailure() throws Exception {
        java.nio.file.Path dir = Files.createTempDirectory(Paths.get("target"), "t04-partial-");
        ReflectionTestUtils.setField(reportService,"exportDir",dir.toString());
        com.lanf.entity.Shop shop = new com.lanf.entity.Shop();
        shop.setOpen_time("09:00"); shop.setSettle_time("22:00"); shop.setClose_time("23:00");
        when(shopService.getById(1)).thenReturn(shop);
        AtomicInteger queries = new AtomicInteger();
        when(orderAggregate.row(any(),any(),any(),any())).thenAnswer(call -> {
            if (queries.incrementAndGet() == 2) throw new IllegalStateException("second day failed");
            return Arrays.asList(call.getArgument(1),"1","1.00","1.00","0.00","0.00","0.00");
        });
        Map<String,Object> filters=new LinkedHashMap<>();
        filters.put("date","2025-01-01"); filters.put("endDate","2025-01-02");
        reportService.createReportExportJob(1,5,"daily",filters,"csv");
        assertEquals("FAILED",inserted.get().getStatus()); assertNull(inserted.get().getDownload_token());
        verify(orderAggregate).row(1,"2025-01-01","2025-01-01 22:00:00","2025-01-02 22:00:00");
        try (java.util.stream.Stream<java.nio.file.Path> files=Files.list(dir)) {
            assertEquals(0, files.count(), "失败任务不得留下可下载的部分 CSV 文件");
        }
        Files.delete(dir);
    }
    // ---------------- 2) 导出任务 token 过期判断 ----------------

    @Test
    void downloadTokenExpiryJudgement() {
        LocalDateTime now = LocalDateTime.now(ZONE);
        ReportExportJob done = new ReportExportJob();
        done.setStatus(ReportExportJob.STATUS_DONE);
        done.setDownload_token(ReportExportService.randomToken32());

        done.setToken_expires_at(now.plusMinutes(15));
        assertTrue(ReportExportService.isDownloadTokenUsable(done, now), "未过期应可用");

        done.setToken_expires_at(now.minusSeconds(1));
        assertFalse(ReportExportService.isDownloadTokenUsable(done, now), "过期即不可用");

        done.setToken_expires_at(now.plusMinutes(15));
        done.setDownload_token(null);
        assertFalse(ReportExportService.isDownloadTokenUsable(done, now), "token 缺失不可用");

        ReportExportJob pending = new ReportExportJob();
        pending.setStatus(ReportExportJob.STATUS_PENDING);
        pending.setDownload_token("t");
        pending.setToken_expires_at(now.plusMinutes(15));
        assertFalse(ReportExportService.isDownloadTokenUsable(pending, now), "非 DONE 状态不可用");
    }

    @Test
    void jobListAttachesDownloadUrlOnlyWhenTokenUsable() {
        LocalDateTime now = LocalDateTime.now(ZONE);

        ReportExportJob fresh = new ReportExportJob();
        fresh.setId(9L);
        fresh.setJob_type(ReportExportJob.TYPE_REPORT_EXPORT);
        fresh.setStatus(ReportExportJob.STATUS_DONE);
        fresh.setDownload_token("abcd");
        fresh.setToken_expires_at(now.plusMinutes(5));
        Map<String, Object> ok = reportService.buildJobItem(fresh, now);
        assertEquals("/admin/reports/exports/9/download?token=abcd", ok.get("downloadUrl"));
        assertNull(ok.get("error"));

        ReportExportJob expired = new ReportExportJob();
        expired.setId(10L);
        expired.setJob_type(ReportExportJob.TYPE_REPORT_EXPORT);
        expired.setStatus(ReportExportJob.STATUS_DONE);
        expired.setDownload_token("abcd");
        expired.setToken_expires_at(now.minusMinutes(1));
        Map<String, Object> stale = reportService.buildJobItem(expired, now);
        assertNull(stale.get("downloadUrl"), "过期后 downloadUrl 必须为 null");
        assertEquals("download link expired", stale.get("error"));
        assertEquals("DONE", stale.get("status"), "过期时 status 仍为 DONE");

        ReportExportJob running = new ReportExportJob();
        running.setId(11L);
        running.setJob_type(ReportExportJob.TYPE_REPORT_EXPORT);
        running.setStatus(ReportExportJob.STATUS_RUNNING);
        Map<String, Object> r = reportService.buildJobItem(running, now);
        assertFalse(r.containsKey("downloadUrl"));
    }

    // ---------------- 3) 日志 30 天窗口过滤 ----------------

    @Test
    void onlineWindowRejectsRequestsOlderThan30Days() {
        LocalDateTime now = LocalDateTime.now(ZONE);

        assertNull(AdminLogService.resolveOnlineWindow(now.minusDays(40).format(TS), null, now),
                "startTime 早于 30 天边界 → 越界（空页 + hint）");
        assertNull(AdminLogService.resolveOnlineWindow(now.minusDays(31).format(TS),
                now.minusDays(29).format(TS), now), "跨 30 天边界的窗口也视为越界");
        assertNull(AdminLogService.resolveOnlineWindow(now.plusDays(1).format(TS), null, now),
                "窗口完全在未来 → 越界");

        AdminLogService.Window def = AdminLogService.resolveOnlineWindow(null, null, now);
        assertNotNull(def, "未传时间默认近 30 天");
        assertEquals(now.minusDays(30).format(TS), def.start);
        assertEquals(now.format(TS), def.end);

        AdminLogService.Window recent = AdminLogService.resolveOnlineWindow(
                now.minusDays(3).format(TS), null, now);
        assertNotNull(recent);
        assertEquals(now.minusDays(3).format(TS), recent.start);

        // endTime 超过当前时间：静默截断到 now（不算越界）
        AdminLogService.Window clamped = AdminLogService.resolveOnlineWindow(
                now.minusDays(1).format(TS), now.plusDays(1).format(TS), now);
        assertNotNull(clamped);
        assertEquals(now.format(TS), clamped.end);
    }

    @Test
    @SuppressWarnings("unchecked")
    void queryLogsReturnsEmptyPageWithHintWhenOutOfRange() {
        String tooOld = LocalDateTime.now(ZONE).minusDays(40).format(TS);
        Map<String, Object> out = logService.queryLogs(1, "settings", null, null, tooOld, null, 1, 20);

        assertEquals(0, ((Number) out.get("total")).intValue());
        assertTrue(((List<?>) out.get("items")).isEmpty());
        assertNotNull(out.get("hint"), "越界空页必须附 hint");
        assertTrue(String.valueOf(out.get("hint")).contains("归档"));
        verify(operationLogService, never()).page(any(), any());
    }

    @Test
    @SuppressWarnings("unchecked")
    void queryLogsAppliesMaskingOnSnapshotAndReason() {
        com.baomidou.mybatisplus.extension.plugins.pagination.Page<OperationLog> page =
                new com.baomidou.mybatisplus.extension.plugins.pagination.Page<>(1, 20);
        page.setRecords(Collections.singletonList(logRow("{\"phone\":\"13812345678\"}")));
        page.setTotal(1);
        when(operationLogService.page(any(), any(Wrapper.class))).thenReturn(page);

        String recent = LocalDateTime.now(ZONE).minusDays(1).format(TS);
        Map<String, Object> out = logService.queryLogs(1, null, null, null, recent, null, 1, 20);

        assertEquals(1, ((Number) out.get("total")).intValue());
        Map<String, Object> item = (Map<String, Object>) ((List<?>) out.get("items")).get(0);
        assertEquals("{\"phone\":\"138****5678\"}", item.get("requestSnapshot"), "快照中手机号必须脱敏");
        assertEquals("回访电话138****5678", item.get("reason"));
    }

    // ---------------- 4) 脱敏正则 ----------------

    @Test
    void maskRulesForMobileAndIdCard() {
        assertEquals("138****5678", LogMaskUtil.mask("13812345678"));
        assertEquals("联系 139****5432", LogMaskUtil.mask("联系 13998765432"));

        // 18 位身份证：留前 3 后 4
        assertEquals("110***********7758", LogMaskUtil.mask("110101199003077758"));
        // 末位 X 的 18 位身份证
        assertEquals("110***********775X", LogMaskUtil.mask("11010119900307775X"));
        // 15 位身份证
        assertEquals("110********3077", LogMaskUtil.mask("110101199003077"));

        // 同一句里混排手机号 + 身份证
        String mixed = LogMaskUtil.mask("身份证110101199003077758，手机13998765432");
        assertFalse(mixed.contains("110101199003077758"));
        assertFalse(mixed.contains("13998765432"));
        assertTrue(mixed.contains("110***********7758"));
        assertTrue(mixed.contains("139****5432"));

        // 长数字串中间的子串不误伤（边界断言）
        assertEquals("订单号20240101123456789012", LogMaskUtil.mask("订单号20240101123456789012"));
        assertEquals("无敏感信息", LogMaskUtil.mask("无敏感信息"));
        assertNull(LogMaskUtil.mask(null));
    }

    // ---------------- 5) 归档 job 状态机 ----------------

    @Test
    @SuppressWarnings("unchecked")
    void archiveSearchStateMachinePendingToDoneWithHitCount() {
        when(operationLogService.count(any(Wrapper.class))).thenReturn(7);

        Map<String, Object> cond = new LinkedHashMap<>();
        cond.put("module", "settings");
        Map<String, Object> resp = logService.createArchiveSearch(1, 5, cond);

        assertEquals(1L, resp.get("jobId"));
        assertEquals("PENDING", resp.get("status"));
        assertEquals("ARCHIVE_QUERY_PENDING", resp.get("code"));

        assertEquals("PENDING", statusAtInsert.get(), "落库时状态必须为 PENDING");
        ReportExportJob job = inserted.get();
        assertEquals(ReportExportJob.TYPE_ARCHIVE_SEARCH, job.getJob_type());
        assertEquals("DONE", job.getStatus(), "同步执行器下应内联到 DONE");
        assertTrue(job.getResult_summary_json().contains("\"hitCount\":7"));
        assertTrue(job.getResult_summary_json().contains("结果请至归档存储查看"));
        assertTrue(job.getResult_summary_json().contains("365"), "摘要应说明 1 年保留边界");

        when(jobMapper.selectById(job.getId())).thenReturn(job);
        Map<String, Object> view = logService.getArchiveSearchJob(1, job.getId());
        assertEquals("DONE", view.get("status"));
        assertEquals(7, ((Number) view.get("hitCount")).intValue());
        assertEquals("结果请至归档存储查看", view.get("hint"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void archiveSearchFailureMarksFailed() {
        when(operationLogService.count(any(Wrapper.class))).thenThrow(new RuntimeException("archive offline"));

        Map<String, Object> resp = logService.createArchiveSearch(1, 5, new LinkedHashMap<>());
        assertEquals("PENDING", resp.get("status"), "受理响应始终为 202 语义的 PENDING");

        ReportExportJob job = inserted.get();
        assertEquals("FAILED", job.getStatus());
        assertNotNull(job.getError());
        assertTrue(job.getError().contains("archive offline"));

        ApiException notFound = assertThrows(ApiException.class, () -> logService.getArchiveSearchJob(1, 999L));
        assertEquals(404, notFound.getHttpStatus());
        assertEquals("ARCHIVE_JOB_NOT_FOUND", notFound.getErrorCode());
    }

    @Test
    void archiveWindowClampsTo30dTo365dAndExportWindowTo1Year() {
        LocalDateTime now = LocalDateTime.now(ZONE);

        // 归档窗：请求 400 天前 → 裁剪到 now-365d；end 裁剪到 now-30d
        AdminLogService.Window w = AdminLogService.resolveArchiveWindow(
                single("startTime", now.minusDays(400).format(TS)), now);
        assertNotNull(w);
        assertEquals(now.minusDays(365).format(TS), w.start, "超过 365 天的数据不返回（1 年销毁）");
        assertEquals(now.minusDays(30).format(TS), w.end, "30 天内数据走在线查询");

        // 请求窗完全落在近 30 天 → 归档无交集
        assertNull(AdminLogService.resolveArchiveWindow(
                pair("startTime", now.minusDays(10).format(TS), "endTime", now.format(TS)), now));
        // 请求窗完全早于 365 天 → 已销毁，无交集
        assertNull(AdminLogService.resolveArchiveWindow(
                pair("startTime", now.minusDays(400).format(TS), "endTime", now.minusDays(380).format(TS)), now));

        // 导出窗：裁剪到近 1 年 [now-365d, now]
        AdminLogService.Window e = AdminLogService.resolveExportWindow(
                single("startTime", now.minusDays(400).format(TS)), now);
        assertEquals(now.minusDays(365).format(TS), e.start);
        assertEquals(now.format(TS), e.end);
    }

    // ---------------- 6) 日志导出：purpose 必填 + 同步 CSV ----------------

    @Test
    void logExportRequiresPurpose() {
        ApiException missing = assertThrows(ApiException.class,
                () -> logService.createLogExport(1, 5, new LinkedHashMap<>(), null));
        assertEquals(400, missing.getHttpStatus());
        assertEquals("LOG_EXPORT_PURPOSE_REQUIRED", missing.getErrorCode());

        ApiException blank = assertThrows(ApiException.class,
                () -> logService.createLogExport(1, 5, new LinkedHashMap<>(), "   "));
        assertEquals("LOG_EXPORT_PURPOSE_REQUIRED", blank.getErrorCode());

        verify(jobMapper, never()).insert(any(ReportExportJob.class));
    }

    @Test
    @SuppressWarnings("unchecked")
    void logExportGeneratesMaskedCsvWithAuditNo() throws Exception {
        when(operationLogService.list(any(Wrapper.class)))
                .thenReturn(Collections.singletonList(logRow("{\"phone\":\"13812345678\"}")));

        Map<String, Object> query = new LinkedHashMap<>();
        query.put("module", "settings");
        Map<String, Object> resp = logService.createLogExport(1, 5, query, "安全审计复查");

        ReportExportJob job = inserted.get();
        assertEquals(ReportExportJob.TYPE_LOG_EXPORT, job.getJob_type());
        assertEquals("DONE", job.getStatus());
        assertEquals(job.getId(), resp.get("jobId"));
        String auditNo = String.valueOf(resp.get("auditNo"));
        assertTrue(auditNo.matches("LOGEXP-\\d{8}-\\d{6}-[0-9a-f]{4}"),
                "auditNo 格式 LOGEXP-yyyyMMdd-HHmmss-xxxx，实际=" + auditNo);
        assertTrue(job.getResult_summary_json().contains(auditNo));
        assertTrue(job.getResult_summary_json().contains("安全审计复查"));

        String csv = new String(Files.readAllBytes(Paths.get(EXPORT_DIR, job.getFile_name())), StandardCharsets.UTF_8);
        assertTrue(csv.contains("138****5678"), "导出内容必须脱敏");
        assertFalse(csv.contains("13812345678"), "导出内容不得包含明文手机号");
        assertTrue(csv.contains("settings"));
    }

    // ---------------- 工具 ----------------

    private static Map<String, Object> single(String k, Object v) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put(k, v);
        return m;
    }

    private static Map<String, Object> pair(String k1, Object v1, String k2, Object v2) {
        Map<String, Object> m = single(k1, v1);
        m.put(k2, v2);
        return m;
    }
}
