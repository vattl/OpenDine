package com.lanf.adminlog.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.adminlog.util.LogMaskUtil;
import com.lanf.common.ApiException;
import com.lanf.common.PageResult;
import com.lanf.entity.Admin;
import com.lanf.entity.OperationLog;
import com.lanf.entity.Shop;
import com.lanf.report.entity.ReportExportJob;
import com.lanf.report.service.ReportExportService;
import com.lanf.service.IAdminService;
import com.lanf.service.IOperationLogService;
import com.lanf.service.IShopService;
import com.lanf.util.AdminNameResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import javax.annotation.PostConstruct;
import com.lanf.report.service.ReportJobCoordinator;
import com.lanf.report.service.BoundedJobExecutor;
import java.io.IOException;
import java.security.SecureRandom;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;

/**
 * 日志查询 / 归档检索 / 日志导出服务（协调文档 §2、§4、§5）。
 *
 * 保留策略（查询侧硬边界，超期数据不做返回；物理销毁由存储策略执行）：
 * - 在线查询：仅近 {@value #ONLINE_WINDOW_DAYS} 天；请求时间窗越出 30 天边界 → 直接空页 + hint；
 * - 归档检索：时间窗放宽至 365 天，且只扫 [now-365d, now-30d]；
 * - 日志导出：近 1 年（[now-365d, now]），purpose 必填；
 * - 1 年销毁：超过 365 天的数据一律不返回（见 SQL 注释与本文档 §5）。
 *
 * 异步归档检索由服务内自管的单线程 ExecutorService（命名守护线程 archive-search-worker）执行，
 * 完成后 result_summary_json 存命中数；错误码 ARCHIVE_QUERY_PENDING 见协调文档 §4。
 * 日志内容按协调文档 §1 脱敏（手机号/身份证号正则打码，见 {@link LogMaskUtil}）。
 */
@Service
public class AdminLogService {

    private static final Logger log = LoggerFactory.getLogger(AdminLogService.class);

    public static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss");

    /** 在线日志可查窗口（天） */
    public static final int ONLINE_WINDOW_DAYS = 30;
    /** 归档/导出可及窗口（天）；超过视为已按 1 年销毁策略销毁，不再返回 */
    public static final int ARCHIVE_WINDOW_DAYS = 365;

    /** 归档检索受理中的稳定错误码（协调文档 §4） */
    public static final String CODE_ARCHIVE_QUERY_PENDING = "ARCHIVE_QUERY_PENDING";
    /** 归档检索结果提示 */
    public static final String MSG_ARCHIVE_HINT = "结果请至归档存储查看";
    /** 在线窗口越界空页提示 */
    public static final String MSG_ONLINE_HINT = "仅支持近 30 天在线查询，更早数据请使用归档检索（POST /admin/logs/archive-search）";

    private static final char[] HEX = "0123456789abcdef".toCharArray();
    private static final SecureRandom RANDOM = new SecureRandom();

    @Autowired
    private IOperationLogService operationLogService;
    @Autowired
    private ReportExportService reportExportService;
    @Autowired
    private IAdminService adminService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private ReportJobCoordinator jobCoordinator;

    /** 导出文件输出目录（与报表导出共用 @Value 配置） */
    @Value("${report.export.dir:./data/exports}")
    private String exportDir;

    /** 服务内自管的单线程执行器：命名守护线程（测试可替换为同步执行器） */
    private ExecutorService archiveExecutor = BoundedJobExecutor.create("archive-search-worker");
    private final java.util.Set<Long> scheduled = java.util.concurrent.ConcurrentHashMap.newKeySet();

    @PostConstruct public void registerRecovery() {
        jobCoordinator.register(ReportExportJob.TYPE_ARCHIVE_SEARCH, () -> {
            if (archiveExecutor.isShutdown()) return;
            for (Long id : jobCoordinator.recoverable(ReportExportJob.TYPE_ARCHIVE_SEARCH)) {
                ReportExportJob job = reportExportService.getJob(null,id,ReportExportJob.TYPE_ARCHIVE_SEARCH);
                if (job != null && !submit(job)) break;
            }
        });
    }
    private boolean submit(ReportExportJob job) {
        return BoundedJobExecutor.submit(archiveExecutor, scheduled, job.getId(), () -> runArchiveSearch(job));
    }

    @PreDestroy
    public void shutdown() {
        archiveExecutor.shutdownNow();
    }

    // ---------------- 在线日志查询（近 30 天） ----------------

    /**
     * 在线日志查询：type(module)/操作者(admin_id)/时间筛选 + 分页；仅返回近 30 天。
     * 时间越界直接空页并附 hint（MSG_ONLINE_HINT）。
     */
    /** 兼容重载：不传 category 时不过滤（等价 all，保持旧行为） */
    public Map<String, Object> queryLogs(Integer shopId, String module, String action, Integer operator,
                                         String startTime, String endTime, int page, int pageSize) {
        return queryLogs(shopId, module, action, operator, startTime, endTime, page, pageSize, null);
    }

    /**
     * 在线日志查询：category 分类过滤。
     * business=排除 access_denied 拒绝噪声（默认前端口径）；security=仅安全事件；all=全量。
     */
    public Map<String, Object> queryLogs(Integer shopId, String module, String action, Integer operator,
                                         String startTime, String endTime, int page, int pageSize,
                                         String category) {
        int pn = page > 0 ? page : 1;
        int ps = pageSize > 0 ? Math.min(pageSize, 100) : 20;
        LocalDateTime now = LocalDateTime.now(ZONE);
        Window window = resolveOnlineWindow(startTime, endTime, now);
        Map<String, Object> out = new LinkedHashMap<>();
        if (window == null) {
            // 时间越界：直接空页 + hint，不打库
            out.put("page", pn);
            out.put("pageSize", ps);
            out.put("total", 0L);
            out.put("items", Collections.emptyList());
            out.put("hint", MSG_ONLINE_HINT);
            return out;
        }
        QueryWrapper<OperationLog> q = new QueryWrapper<>();
        applyShopScope(q, shopId);
        if (module != null && !module.trim().isEmpty()) {
            q.eq("module", module.trim());
        }
        if (action != null && !action.trim().isEmpty()) {
            q.eq("action", action.trim());
        }
        if (operator != null) {
            q.eq("admin_id", operator);
        }
        applyCategoryFilter(q, category);
        q.ge("created_at", window.start).le("created_at", window.end);
        q.orderByDesc("created_at");
        IPage<OperationLog> p = operationLogService.page(new Page<>(pn, ps), q);
        out.put("page", pn);
        out.put("pageSize", ps);
        out.put("total", p.getTotal());
        out.put("items", maskAll(p.getRecords()));
        out.put("windowStart", window.start);
        out.put("windowEnd", window.end);
        return out;
    }

    /** 分类过滤：business=排除拒绝噪声；security=仅 security 模块；null/all=全量 */
    static void applyCategoryFilter(QueryWrapper<OperationLog> q, String category) {
        if (category == null || category.trim().isEmpty() || "all".equalsIgnoreCase(category)) {
            return;
        }
        if ("security".equalsIgnoreCase(category)) {
            q.eq("module", "security");
        } else {
            // business 默认：排除 access_denied 拒绝记录（保留权限变更等 security 业务事件）
            q.ne("action", "access_denied");
        }
    }

    /** 门店过滤口径与 AdminOperationLogController 一致：0=全局（无门店历史行），null=总部全量 */
    static void applyShopScope(QueryWrapper<OperationLog> q, Integer shopId) {
        if (shopId == null) {
            return;
        }
        if (shopId == 0) {
            q.and(w -> w.isNull("shop_id").or().eq("shop_id", 0));
        } else {
            q.eq("shop_id", shopId);
        }
    }

    /**
     * 在线窗口解析：请求时间窗必须完全落在近 30 天内（startTime < now-30d 即越界返回 null）；
     * endTime 超过当前时间静默截断到 now；未传则默认 [now-30d, now]。
     * 返回 null = 越界（调用方直接空页 + hint）。公开静态便于单测。
     */
    public static Window resolveOnlineWindow(String startTime, String endTime, LocalDateTime now) {
        LocalDateTime start = parseTime(startTime, false);
        LocalDateTime end = parseTime(endTime, true);
        if (start != null && end != null && start.isAfter(end)) {
            throw new ApiException(400, "LOG_RANGE_INVALID", "startTime 不能晚于 endTime");
        }
        LocalDateTime minOnline = now.minusDays(ONLINE_WINDOW_DAYS);
        if (start != null && start.isBefore(minOnline)) {
            return null; // 越出 30 天在线窗口：空页 + hint
        }
        LocalDateTime effStart = start == null ? minOnline : start;
        LocalDateTime effEnd = end == null ? now : (end.isAfter(now) ? now : end);
        if (effStart.isAfter(effEnd)) {
            return null; // 窗口完全不在近 30 天内
        }
        return new Window(effStart.format(TS), effEnd.format(TS));
    }

    // ---------------- 归档检索（30 天 ~ 1 年，异步） ----------------

    /**
     * 创建归档检索任务（job_type=ARCHIVE_SEARCH，PENDING）并异步扫描 30 天~1 年数据；
     * 响应 {jobId, status:"PENDING", code:"ARCHIVE_QUERY_PENDING"}（协调文档 §4 的 202 语义）。
     */
    public Map<String, Object> createArchiveSearch(int shopId, Integer adminId, Map<String, Object> conditions) {
        if (archiveExecutor.isShutdown()) throw new ApiException(503,"REPORT_WORKER_CLOSED","任务服务正在停止");
        Map<String, Object> cond = conditions == null ? new LinkedHashMap<>() : conditions;
        validateConditions(cond);

        ReportExportJob job = new ReportExportJob();
        job.setShop_id(shopId);
        job.setJob_type(ReportExportJob.TYPE_ARCHIVE_SEARCH);
        job.setReport_type("log");
        job.setFilters_json(toJson(cond));
        job.setFormat(ReportExportJob.FORMAT_CSV);
        job.setStatus(ReportExportJob.STATUS_PENDING);
        job.setCreated_by(adminId);
        LocalDateTime now = LocalDateTime.now(ZONE);
        job.setCreated_at(now);
        job.setUpdated_at(now);
        reportExportService.insertJob(job);
        log.info("[archive-search] job created: id={}, shop={}, conditions={}", job.getId(), shopId, job.getFilters_json());

        submit(job);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("jobId", job.getId());
        out.put("status", ReportExportJob.STATUS_PENDING);
        out.put("code", CODE_ARCHIVE_QUERY_PENDING);
        return out;
    }

    private void validateConditions(Map<String, Object> cond) {
        LocalDateTime start = parseTime(str(cond, "startTime"), false);
        LocalDateTime end = parseTime(str(cond, "endTime"), true);
        if (start != null && end != null && start.isAfter(end)) {
            throw new ApiException(400, "LOG_RANGE_INVALID", "startTime 不能晚于 endTime");
        }
    }

    /**
     * 归档检索执行：状态机 PENDING → RUNNING → DONE（result_summary_json 存命中数）/ FAILED。
     * 只扫 [now-365d, now-30d]：超过 365 天的数据按 1 年销毁策略不再返回（30 天内走在线查询）。
     * 包内可见以便单元测试直接驱动状态机。
     */
    void runArchiveSearch(ReportExportJob job) {
        if (!jobCoordinator.claim(job)) return;
        try {

            Map<String, Object> cond = parseJson(job.getFilters_json());
            LocalDateTime now = LocalDateTime.now(ZONE);
            Window window = resolveArchiveWindow(cond, now);
            long hits = 0;
            if (window != null) {
                QueryWrapper<OperationLog> q = new QueryWrapper<>();
                applyShopScope(q, job.getShop_id());
                String module = str(cond, "module");
                String action = str(cond, "action");
                if (!module.isEmpty()) {
                    q.eq("module", module);
                }
                if (!action.isEmpty()) {
                    q.eq("action", action);
                }
                Integer operator = intOrNull(cond, "operator");
                if (operator != null) {
                    q.eq("admin_id", operator);
                }
                q.ge("created_at", window.start).le("created_at", window.end);
                hits = operationLogService.count((Wrapper<OperationLog>) q);
            }

            Map<String, Object> summary = new LinkedHashMap<>();
            summary.put("hitCount", hits);
            summary.put("windowStart", window == null ? null : window.start);
            summary.put("windowEnd", window == null ? null : window.end);
            summary.put("note", MSG_ARCHIVE_HINT);
            summary.put("retentionPolicy", "在线仅保留 30 天；归档检索窗口为 30 天至 365 天；超过 365 天数据已按存储策略销毁，不再返回");
            job.setResult_summary_json(toJson(summary));
            job.setStatus(ReportExportJob.STATUS_DONE);
            job.setError(null);
            job.setUpdated_at(LocalDateTime.now(ZONE));
            if (!jobCoordinator.finish(job)) return;
            log.info("[archive-search] job done: id={}, hits={}", job.getId(), hits);
        } catch (Exception e) {
            if (archiveExecutor.isShutdown()) return; // restart recovery, not a permanent business failure
            log.error("[archive-search] job failed: id={}, error={}", job.getId(), e.getMessage(), e);
            job.setStatus(ReportExportJob.STATUS_FAILED);
            job.setError(truncate(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage(), 512));
            job.setUpdated_at(LocalDateTime.now(ZONE));
            jobCoordinator.finish(job);
        }
    }

    /** 归档窗口：裁剪到 [now-365d, now-30d]；请求窗与该窗口无交集返回 null（命中 0）。公开静态便于单测 */
    public static Window resolveArchiveWindow(Map<String, Object> cond, LocalDateTime now) {
        LocalDateTime start = parseTime(str(cond, "startTime"), false);
        LocalDateTime end = parseTime(str(cond, "endTime"), true);
        LocalDateTime lower = now.minusDays(ARCHIVE_WINDOW_DAYS);
        LocalDateTime upper = now.minusDays(ONLINE_WINDOW_DAYS);
        LocalDateTime effStart = start == null ? lower : (start.isBefore(lower) ? lower : start);
        LocalDateTime effEnd = end == null ? upper : (end.isAfter(upper) ? upper : end);
        if (effStart.isAfter(effEnd)) {
            return null;
        }
        return new Window(effStart.format(TS), effEnd.format(TS));
    }

    /** 归档检索任务状态查询：DONE 时附命中数与「结果请至归档存储查看」提示 */
    public Map<String, Object> getArchiveSearchJob(int shopId, Long jobId) {
        ReportExportJob job = reportExportService.getJob(shopId, jobId, ReportExportJob.TYPE_ARCHIVE_SEARCH);
        if (job == null) {
            throw new ApiException(404, "ARCHIVE_JOB_NOT_FOUND", "归档检索任务不存在");
        }
        Map<String, Object> item = reportExportService.buildJobItem(job, LocalDateTime.now(ZONE));
        if (ReportExportJob.STATUS_DONE.equals(job.getStatus())) {
            Map<String, Object> summary = reportExportService.parseSummary(job.getResult_summary_json());
            item.put("hitCount", summary.get("hitCount"));
            item.put("hint", MSG_ARCHIVE_HINT);
        }
        return item;
    }

    // ---------------- 日志导出（近 1 年，同步，仅超管权限在拦截器层） ----------------

    /**
     * 创建 LOG_EXPORT 任务并同步生成 CSV（近 1 年内）；purpose 必填，缺失 400。
     * 返回 {jobId, auditNo}，auditNo 格式 LOGEXP-yyyyMMdd-HHmmss-xxxx。
     */
    public Map<String, Object> createLogExport(int shopId, Integer adminId, Map<String, Object> query, String purpose) {
        if (purpose == null || purpose.trim().isEmpty()) {
            throw new ApiException(400, "LOG_EXPORT_PURPOSE_REQUIRED", "日志导出必须填写用途 purpose");
        }
        Map<String, Object> filters = query == null ? new LinkedHashMap<>() : new LinkedHashMap<>(query);
        filters.put("purpose", purpose.trim());

        ReportExportJob job = new ReportExportJob();
        job.setShop_id(shopId);
        job.setJob_type(ReportExportJob.TYPE_LOG_EXPORT);
        job.setReport_type("log");
        job.setFilters_json(toJson(filters));
        job.setFormat(ReportExportJob.FORMAT_CSV);
        job.setStatus(ReportExportJob.STATUS_PENDING);
        job.setCreated_by(adminId);
        LocalDateTime now = LocalDateTime.now(ZONE);
        job.setCreated_at(now);
        job.setUpdated_at(now);
        reportExportService.insertJob(job);

        String auditNo = newAuditNo(now);
        runLogExport(job, auditNo);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("jobId", job.getId());
        out.put("auditNo", auditNo);
        return out;
    }

    /** 审计号：LOGEXP-yyyyMMdd-HHmmss-xxxx（xxxx 为 4 位随机十六进制） */
    static String newAuditNo(LocalDateTime now) {
        byte[] b = new byte[2];
        RANDOM.nextBytes(b);
        char[] tail = new char[4];
        for (int i = 0; i < b.length; i++) {
            tail[i * 2] = HEX[(b[i] >> 4) & 0xf];
            tail[i * 2 + 1] = HEX[b[i] & 0xf];
        }
        return String.format(Locale.ROOT, "LOGEXP-%s-%s", now.format(STAMP), new String(tail));
    }

    /**
     * 同步生成日志导出 CSV：近 1 年（[now-365d, now] ∩ 请求窗），内容脱敏；
     * 成功 → DONE + 下载令牌 + 摘要（auditNo/hitCount/purpose）；失败 → FAILED 并抛 LOG_EXPORT_FAILED。
     * 包内可见以便单元测试。
     */
    void runLogExport(ReportExportJob job, String auditNo) {
        try {
            job.setStatus(ReportExportJob.STATUS_RUNNING);
            job.setUpdated_at(LocalDateTime.now(ZONE));
            reportExportService.updateJob(job);

            Map<String, Object> filters = parseJson(job.getFilters_json());
            LocalDateTime now = LocalDateTime.now(ZONE);
            Window window = resolveExportWindow(filters, now);

            QueryWrapper<OperationLog> q = new QueryWrapper<>();
            applyShopScope(q, job.getShop_id());
            String module = str(filters, "module");
            String action = str(filters, "action");
            if (!module.isEmpty()) {
                q.eq("module", module);
            }
            if (!action.isEmpty()) {
                q.eq("action", action);
            }
            Integer operator = intOrNull(filters, "operator");
            if (operator != null) {
                q.eq("admin_id", operator);
            }
            q.ge("created_at", window.start).le("created_at", window.end);
            q.orderByAsc("created_at");
            List<OperationLog> rows = operationLogService.list((Wrapper<OperationLog>) q);

            List<String> header = Arrays.asList("id", "created_at", "shop_id", "module", "action", "admin_id",
                    "ip", "target_id", "result_status", "reason", "request_snapshot", "before_state",
                    "after_state", "trace_id");
            List<List<String>> lines = new ArrayList<>();
            if (rows != null) {
                for (OperationLog row : rows) {
                    lines.add(exportLine(row));
                }
            }
            String fileName = String.format("log_export_shop%d_%s_%d.csv",
                    job.getShop_id(), LocalDateTime.now(ZONE).format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss")), job.getId());
            ReportExportService.writeCsv(exportDir, fileName, header, lines);

            ReportExportService.issueDownloadToken(job, now);
            job.setFile_name(fileName);
            job.setStatus(ReportExportJob.STATUS_DONE);
            job.setError(null);
            Map<String, Object> summary = new LinkedHashMap<>();
            summary.put("auditNo", auditNo);
            summary.put("hitCount", lines.size());
            summary.put("purpose", str(filters, "purpose"));
            summary.put("windowStart", window.start);
            summary.put("windowEnd", window.end);
            summary.put("retentionPolicy", "日志导出窗口为近 1 年（365 天）；超过 365 天数据已按存储策略销毁，不再返回");
            job.setResult_summary_json(toJson(summary));
            job.setUpdated_at(LocalDateTime.now(ZONE));
            reportExportService.updateJob(job);
            log.info("[log-export] job done: id={}, auditNo={}, rows={}", job.getId(), auditNo, lines.size());
        } catch (Exception e) {
            log.error("[log-export] job failed: id={}, error={}", job.getId(), e.getMessage(), e);
            job.setStatus(ReportExportJob.STATUS_FAILED);
            job.setError(truncate(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage(), 512));
            job.setUpdated_at(LocalDateTime.now(ZONE));
            reportExportService.updateJob(job);
            throw new ApiException(500, "LOG_EXPORT_FAILED", "日志导出失败，请稍后重试");
        }
    }

    /** 导出窗口：裁剪到近 1 年 [now-365d, now]；超过 365 天的数据不返回。公开静态便于单测 */
    public static Window resolveExportWindow(Map<String, Object> filters, LocalDateTime now) {
        LocalDateTime start = parseTime(str(filters, "startTime"), false);
        LocalDateTime end = parseTime(str(filters, "endTime"), true);
        LocalDateTime lower = now.minusDays(ARCHIVE_WINDOW_DAYS);
        LocalDateTime effStart = start == null ? lower : (start.isBefore(lower) ? lower : start);
        LocalDateTime effEnd = end == null ? now : (end.isAfter(now) ? now : end);
        if (effStart.isAfter(effEnd)) {
            // 请求窗完全超出近 1 年：空窗口（导出仅含表头）
            return new Window(now.format(TS), now.format(TS));
        }
        return new Window(effStart.format(TS), effEnd.format(TS));
    }

    static List<String> exportLine(OperationLog row) {
        return Arrays.asList(
                row.getId() == null ? "" : String.valueOf(row.getId()),
                isoDate(row.getCreated_at()),
                row.getShop_id() == null ? "" : String.valueOf(row.getShop_id()),
                nvlStr(row.getModule()),
                nvlStr(row.getAction()),
                row.getAdmin_id() == null ? "" : String.valueOf(row.getAdmin_id()),
                nvlStr(row.getIp()),
                nvlStr(LogMaskUtil.mask(row.getTarget_id())),
                nvlStr(row.getResult_status()),
                nvlStr(LogMaskUtil.mask(row.getReason())),
                nvlStr(LogMaskUtil.mask(row.getRequest_snapshot())),
                nvlStr(LogMaskUtil.mask(row.getBefore_state())),
                nvlStr(LogMaskUtil.mask(row.getAfter_state())),
                nvlStr(row.getTrace_id()));
    }

    // ---------------- 脱敏与视图 ----------------

    /** 列表项脱敏：快照/前后状态/原因中手机号、身份证号打码；并批量回填管理员姓名与门店名称 */
    List<Map<String, Object>> maskAll(List<OperationLog> rows) {
        List<Map<String, Object>> items = new ArrayList<>();
        if (rows == null || rows.isEmpty()) {
            return items;
        }
        Map<Integer, String> adminNames = resolveNames(
                collectIds(rows, true), false);
        Map<Integer, String> shopNames = resolveNames(
                collectIds(rows, false), true);
        for (OperationLog row : rows) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", row.getId());
            item.put("shopId", row.getShop_id());
            item.put("module", row.getModule());
            item.put("action", row.getAction());
            item.put("adminId", row.getAdmin_id());
            String adminDisplayName = row.getAdmin_id() == null ? null : adminNames.get(row.getAdmin_id());
            item.put("adminName", adminDisplayName);
            item.put("operator_name", adminDisplayName);
            item.put("shopName", row.getShop_id() == null ? null : shopNames.get(row.getShop_id()));
            item.put("ip", row.getIp());
            item.put("targetId", row.getTarget_id());
            item.put("resultStatus", row.getResult_status());
            item.put("resultCode", row.getResult_code());
            item.put("traceId", row.getTrace_id());
            item.put("category", "security".equals(row.getModule()) ? "security" : "business");
            item.put("createdAt", isoDate(row.getCreated_at()));
            item.put("reason", LogMaskUtil.mask(row.getReason()));
            item.put("requestSnapshot", LogMaskUtil.mask(row.getRequest_snapshot()));
            item.put("beforeState", LogMaskUtil.mask(row.getBefore_state()));
            item.put("afterState", LogMaskUtil.mask(row.getAfter_state()));
            items.add(item);
        }
        return items;
    }

    /** 收集一页记录中的 admin_id（wantAdmin=true）或 shop_id（false），去重 */
    private static java.util.Set<Integer> collectIds(List<OperationLog> rows, boolean wantAdmin) {
        java.util.Set<Integer> ids = new java.util.LinkedHashSet<>();
        for (OperationLog row : rows) {
            Integer v = wantAdmin ? row.getAdmin_id() : row.getShop_id();
            if (v != null) {
                ids.add(v);
            }
        }
        return ids;
    }

    /** 批量查 t_admin.userName/realName / t_shop.name；服务缺失或查询失败时静默返回空映射，不阻断日志查询 */
    private Map<Integer, String> resolveNames(java.util.Set<Integer> ids, boolean shop) {
        Map<Integer, String> names = new java.util.HashMap<>();
        if (ids == null || ids.isEmpty()) {
            return names;
        }
        try {
            if (shop) {
                if (shopService == null) {
                    return names;
                }
                for (Shop s : shopService.listByIds(ids)) {
                    if (s != null && s.getId() != null) {
                        names.put(s.getId(), s.getName());
                    }
                }
            } else {
                if (adminService == null) {
                    return names;
                }
                for (Admin a : adminService.listByIds(ids)) {
                    if (a != null && a.getId() != null) {
                        names.put(a.getId(), AdminNameResolver.resolveDisplayName(a));
                    }
                }
            }
        } catch (RuntimeException e) {
            log.warn("日志名称回填失败: shop={}, count={}, error={}", shop, ids.size(), e.getMessage());
        }
        return names;
    }

    // ---------------- 工具 ----------------

    /** 查询窗口（已格式化为 yyyy-MM-dd HH:mm:ss 字符串）。公开便于单测断言 */
    public static final class Window {
        public final String start;
        public final String end;

        Window(String start, String end) {
            this.start = start;
            this.end = end;
        }
    }

    /** 解析 yyyy-MM-dd / yyyy-MM-dd HH:mm:ss / ISO 时间；空返回 null；非法抛 400 */
    static LocalDateTime parseTime(String raw, boolean endOfDay) {
        if (raw == null || raw.trim().isEmpty()) {
            return null;
        }
        String s = raw.trim();
        try {
            if (s.matches("^\\d{4}-\\d{2}-\\d{2}$")) {
                LocalDate d = LocalDate.parse(s);
                return endOfDay ? d.atTime(LocalTime.of(23, 59, 59)) : d.atStartOfDay();
            }
            if (s.length() == 19 && s.charAt(10) == ' ') {
                return LocalDateTime.parse(s, TS);
            }
            return LocalDateTime.parse(s);
        } catch (Exception e) {
            throw new ApiException(400, "LOG_TIME_INVALID", "时间格式须为 yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss");
        }
    }

    static String str(Map<String, Object> m, String key) {
        if (m == null) {
            return "";
        }
        Object v = m.get(key);
        return v == null ? "" : String.valueOf(v).trim();
    }

    static Integer intOrNull(Map<String, Object> m, String key) {
        Object v = m == null ? null : m.get(key);
        if (v == null || String.valueOf(v).trim().isEmpty()) {
            return null;
        }
        try {
            return Integer.valueOf(String.valueOf(v).trim());
        } catch (NumberFormatException e) {
            throw new ApiException(400, "LOG_OPERATOR_INVALID", "operator 必须为管理员 ID（整数）");
        }
    }

    Map<String, Object> parseJson(String json) {
        if (json == null || json.trim().isEmpty()) {
            return new LinkedHashMap<>();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<LinkedHashMap<String, Object>>() {
            });
        } catch (Exception e) {
            throw new ApiException(500, "LOG_FILTER_PARSE_FAILED", "任务条件解析失败");
        }
    }

    String toJson(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            throw new ApiException(500, "LOG_SERIALIZE_FAILED", "任务条件序列化失败");
        }
    }

    static String isoDate(Date date) {
        return date == null ? null : date.toInstant().atZone(ZONE).format(ISO);
    }

    private static String nvlStr(String v) {
        return v == null ? "" : v;
    }

    private static String truncate(String s, int limit) {
        return s.length() <= limit ? s : s.substring(0, limit);
    }
}
