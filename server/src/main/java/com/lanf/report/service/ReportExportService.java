package com.lanf.report.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.common.PageResult;
import com.lanf.entity.Shop;
import com.lanf.report.entity.ReportExportJob;
import com.lanf.report.mapper.ReportExportJobMapper;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.service.IShopService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import javax.annotation.PostConstruct;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.SecureRandom;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;

/**
 * 报表导出任务服务（协调文档 §2「报表导出任务」）：
 * POST 创建 PENDING 任务后由服务内自管的单线程 ExecutorService（命名守护线程 report-export-worker）
 * 异步生成 CSV 到 {@code ${report.export.dir:./data/exports}}；完成后生成 32 位随机 download_token，
 * token_expires_at = now + 15 分钟（下载地址短期有效）；失败置 FAILED + error。
 *
 * 行数据由 SQL 聚合后逐行写出，保持导出历史口径（不同于同步报表接口）：
 * transac_status='success' 且已接单，输出总应收与净额（扣除优惠、退款和赠送金）；daily 按营业日
 *（open_time 起点 / settle_time 截止，门店配置优先）切行，weekly/monthly 按自然日期区间聚合一行）。
 */
@Service
public class ReportExportService {

    private static final Logger log = LoggerFactory.getLogger(ReportExportService.class);

    public static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;
    private static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyyMMddHHmmss");

    /** 下载令牌有效期（分钟）：地址短期有效 */
    public static final int TOKEN_TTL_MINUTES = 15;
    /** 下载链接过期时的统一提示文案 */
    public static final String MSG_LINK_EXPIRED = "download link expired";

    private static final String[] SUPPORTED_REPORT_TYPES = {"daily", "weekly", "monthly"};

    @Autowired
    private ReportExportJobMapper reportExportJobMapper;
    @Autowired
    private ReportOrderAggregate orderAggregate;
    @Autowired
    private IShopService shopService;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private ReportJobCoordinator jobCoordinator;

    /** 导出文件输出目录（@Value 可配置，默认工作目录下 ./data/exports） */
    @Value("${report.export.dir:./data/exports}")
    private String exportDir;

    /** 服务内自管的单线程执行器：命名守护线程，禁止用于它途（测试可替换为同步执行器） */
    private ExecutorService exportExecutor = BoundedJobExecutor.create("report-export-worker");
    private final java.util.Set<Long> scheduled = java.util.concurrent.ConcurrentHashMap.newKeySet();

    @PostConstruct public void registerRecovery() {
        jobCoordinator.register(ReportExportJob.TYPE_REPORT_EXPORT, () -> {
            if (exportExecutor.isShutdown()) return;
            for (Long id : jobCoordinator.recoverable(ReportExportJob.TYPE_REPORT_EXPORT)) {
                ReportExportJob job = reportExportJobMapper.selectById(id);
                if (job != null && !submit(job)) break;
            }
        });
    }

    private boolean submit(ReportExportJob job) {
        return BoundedJobExecutor.submit(exportExecutor, scheduled, job.getId(), () -> runReportJob(job));
    }

    @PreDestroy
    public void shutdown() {
        exportExecutor.shutdownNow();
    }

    // ---------------- 创建任务 ----------------

    /**
     * 创建报表导出任务（PENDING），异步生成；响应 {jobId, status}。
     *
     * @param shopId     门店上下文（必填）
     * @param adminId    当前管理员
     * @param reportType daily/weekly/monthly
     * @param filters    筛选：{date} 或 {startDate,endDate}（daily 可只传 date）
     * @param format     仅支持 csv
     */
    public Map<String, Object> createReportExportJob(int shopId, Integer adminId, String reportType,
                                                     Map<String, Object> filters, String format) {
        if (exportExecutor.isShutdown()) throw new ApiException(503, "REPORT_WORKER_CLOSED", "任务服务正在停止");
        String type = reportType == null ? "" : reportType.trim().toLowerCase(Locale.ROOT);
        if (type.isEmpty()) {
            throw new ApiException(400, "REPORT_TYPE_REQUIRED", "reportType 不能为空（daily/weekly/monthly）");
        }
        if (!Arrays.asList(SUPPORTED_REPORT_TYPES).contains(type)) {
            throw new ApiException(400, "REPORT_TYPE_INVALID", "reportType 仅支持 daily/weekly/monthly");
        }
        String fmt = format == null ? ReportExportJob.FORMAT_CSV : format.trim().toLowerCase(Locale.ROOT);
        if (fmt.isEmpty()) {
            fmt = ReportExportJob.FORMAT_CSV;
        }
        if (!ReportExportJob.FORMAT_CSV.equals(fmt)) {
            throw new ApiException(400, "REPORT_FORMAT_INVALID", "format 仅支持 csv");
        }
        validateRange(type, filters);

        ReportExportJob job = new ReportExportJob();
        job.setShop_id(shopId);
        job.setJob_type(ReportExportJob.TYPE_REPORT_EXPORT);
        job.setReport_type(type);
        job.setFilters_json(json(filters == null ? new LinkedHashMap<String, Object>() : filters));
        job.setFormat(fmt);
        job.setStatus(ReportExportJob.STATUS_PENDING);
        job.setCreated_by(adminId);
        LocalDateTime now = LocalDateTime.now(ZONE);
        job.setCreated_at(now);
        job.setUpdated_at(now);
        jobCoordinator.admit(shopId, () -> reportExportJobMapper.insert(job));
        log.info("[report-export] job created: id={}, shop={}, type={}, filters={}",
                job.getId(), shopId, type, job.getFilters_json());

        // 响应在提交异步前构建，保证契约恒为 {jobId, status:"PENDING"}
        Map<String, Object> result = jobCreatedResult(job);
        submit(job); // rejected wakeup stays PENDING in the database for recovery
        return result;
    }

    private static Map<String, Object> jobCreatedResult(ReportExportJob job) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("jobId", job.getId());
        out.put("status", job.getStatus());
        return out;
    }

    private void validateRange(String type, Map<String, Object> filters) {
        if (filters != null) {
            if (str(filters, "startDate").isEmpty()) {
                if (!str(filters, "startTime").isEmpty()) filters.put("startDate", str(filters, "startTime"));
                else if (!str(filters, "start").isEmpty()) filters.put("startDate", str(filters, "start"));
            }
            if (str(filters, "endDate").isEmpty()) {
                if (!str(filters, "endTime").isEmpty()) filters.put("endDate", str(filters, "endTime"));
                else if (!str(filters, "end").isEmpty()) filters.put("endDate", str(filters, "end"));
            }
            for (String key : Arrays.asList("date", "startDate", "endDate")) {
                String val = str(filters, key);
                if (!val.isEmpty()) {
                    filters.put(key, extractDateOnly(val));
                }
            }
        }
        String date = str(filters, "date");
        String start = str(filters, "startDate");
        String end = str(filters, "endDate");
        boolean daily = "daily".equals(type);
        if (daily ? date.isEmpty() && start.isEmpty() : start.isEmpty() || end.isEmpty()) {
            throw new ApiException(400, "REPORT_RANGE_REQUIRED", "请提供起止日期（daily 可只提供 date）");
        }
        try {
            // Validate supplied fields too, even when daily's date takes precedence over startDate.
            for (String value : Arrays.asList(date, start, end)) {
                if (!value.isEmpty()) {
                    if (!value.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}")) throw new IllegalArgumentException("invalid date format");
                    LocalDate parsed = LocalDate.parse(value);
                    if (parsed.getYear() < 1000 || parsed.getYear() > 9998)
                        throw new IllegalArgumentException("unsupported database date");
                }
            }
            LocalDate first = LocalDate.parse(daily && !date.isEmpty() ? date : start);
            LocalDate last = end.isEmpty() ? first : LocalDate.parse(end);
            if (last.isBefore(first) || java.time.temporal.ChronoUnit.DAYS.between(first,last) >= 92)
                throw new IllegalArgumentException("range exceeds budget");
        } catch (RuntimeException e) {
            throw new ApiException(400, "REPORT_RANGE_INVALID", "日期须为 yyyy-MM-dd（1000至9998年），起止有序且含首尾最多92天");
        }
    }

    private static String extractDateOnly(String val) {
        if (val == null) return "";
        String s = val.trim().replace('T', ' ');
        if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
            return s.substring(0, 10);
        }
        return s;
    }
    // ---------------- 异步生成 ----------------

    /**
     * 执行单个导出任务：PENDING/RUNNING → 生成 CSV → DONE（+token）/FAILED（+error）。
     * 包内可见以便单元测试直接驱动状态机。
     */
    void runReportJob(ReportExportJob job) {
        if (!jobCoordinator.claim(job)) return;
        try {

            Map<String, Object> filters = parseFilters(job.getFilters_json());
            validateRange(job.getReport_type(), filters); // also protect recovery of old persisted jobs
            List<String> header = Arrays.asList("business_date", "order_count", "total_amount", "net_amount",
                    "discount_amount", "service_fee", "refund_amount", "receivable_charged_amount",
                    "receivable_collected_amount", "receivable_writeoff_amount", "receivable_reversed_amount");

            String fileName = String.format("report_%s_shop%d_%s_%d_%s.csv",
                    job.getReport_type(), job.getShop_id(), LocalDateTime.now(ZONE).format(STAMP), job.getId(), job.getRun_token());
            writeReportCsv(job, filters, fileName, header);

            job.setFile_name(fileName);
            job.setStatus(ReportExportJob.STATUS_DONE);
            issueDownloadToken(job, LocalDateTime.now(ZONE));
            job.setError(null);
            job.setUpdated_at(LocalDateTime.now(ZONE));
            if (!jobCoordinator.finish(job)) return; // a newer lease owns the public result
            log.info("[report-export] job done: id={}, file={}", job.getId(), fileName);
        } catch (Exception e) {
            if (exportExecutor.isShutdown()) return; // leave the interrupted attempt recoverable after its lease
            log.error("[report-export] job failed: id={}, error={}", job.getId(), e.getMessage(), e);
            job.setStatus(ReportExportJob.STATUS_FAILED);
            job.setError(truncate(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage(), 512));
            job.setUpdated_at(LocalDateTime.now(ZONE));
            jobCoordinator.finish(job);
        }
    }

    /** 生成 32 位随机 download_token，并设置 15 分钟有效期（日志导出任务同样复用） */
    public static void issueDownloadToken(ReportExportJob job, LocalDateTime now) {
        job.setDownload_token(randomToken32());
        job.setToken_expires_at(now.plusMinutes(TOKEN_TTL_MINUTES));
    }

    private static final char[] HEX = "0123456789abcdef".toCharArray();
    private static final SecureRandom RANDOM = new SecureRandom();

    public static String randomToken32() {
        byte[] bytes = new byte[16];
        RANDOM.nextBytes(bytes);
        char[] out = new char[32];
        for (int i = 0; i < bytes.length; i++) {
            out[i * 2] = HEX[(bytes[i] >> 4) & 0xf];
            out[i * 2 + 1] = HEX[bytes[i] & 0xf];
        }
        return new String(out);
    }

    // ---------------- SQL aggregate -> one CSV row at a time ----------------

    private void writeReportCsv(ReportExportJob job, Map<String,Object> filters,
                                String fileName, List<String> header) throws IOException {
        Path folder = Paths.get(exportDir);
        Files.createDirectories(folder);
        Path target = folder.resolve(fileName);
        Path partial = folder.resolve(fileName + ".part");
        try (BufferedWriter writer = Files.newBufferedWriter(partial, StandardCharsets.UTF_8)) {
            writer.write('\uFEFF');
            writeRow(writer, header);
            Integer shopId = job.getShop_id();
            Shop shop = shopId == null ? null : shopService.getById(shopId);
            if ("daily".equals(job.getReport_type())) {
                LocalDate start = LocalDate.parse(str(filters,"date").isEmpty() ? str(filters,"startDate") : str(filters,"date"));
                LocalDate end = str(filters,"endDate").isEmpty() ? start : LocalDate.parse(str(filters,"endDate"));
                for (LocalDate day = start; !day.isAfter(end); day = day.plusDays(1)) {
                    if (exportExecutor.isShutdown() || Thread.currentThread().isInterrupted())
                        throw new java.io.InterruptedIOException("report worker stopping");
                    writeRow(writer, orderAggregate.row(shopId, day.toString(),
                            ShopBusinessWindowResolver.settlementWindowText(shop, day)[0],
                            ShopBusinessWindowResolver.settlementWindowText(shop, day)[1]));
                }
            } else {
                LocalDate start = LocalDate.parse(str(filters,"startDate"));
                LocalDate end = LocalDate.parse(str(filters,"endDate"));
                String[] window = ShopBusinessWindowResolver.settlementWindowRangeText(shop, start, end);
                writeRow(writer, orderAggregate.row(shopId, start+"~"+end, window[0], window[1]));
            }
            writer.flush();
        } catch (IOException | RuntimeException failure) {
            Files.deleteIfExists(partial);
            throw failure;
        }
        try {
            Files.move(partial, target, StandardCopyOption.ATOMIC_MOVE);
        } catch (java.nio.file.AtomicMoveNotSupportedException ignored) {
            Files.move(partial, target, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private static void writeRow(BufferedWriter writer, List<String> row) throws IOException {
        writer.write(toCsvLine(row));
        writer.newLine();
    }
    // ---------------- CSV 输出 ----------------

    public static void writeCsv(String dir, String fileName, List<String> header, List<List<String>> rows) throws IOException {
        Path folder = Paths.get(dir);
        Files.createDirectories(folder);
        Path file = folder.resolve(fileName);
        try (BufferedWriter w = Files.newBufferedWriter(file, StandardCharsets.UTF_8)) {
            w.write('\uFEFF'); // BOM，便于 Excel 识别 UTF-8
            w.write(toCsvLine(header));
            w.newLine();
            for (List<String> row : rows) {
                w.write(toCsvLine(row));
                w.newLine();
            }
        }
    }

    public static String toCsvLine(List<String> cells) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < cells.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(csvEscape(cells.get(i)));
        }
        return sb.toString();
    }

    public static String csvEscape(String v) {
        String s = v == null ? "" : v;
        if (s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")) {
            return '"' + s.replace("\"", "\"\"") + '"';
        }
        return s;
    }

    // ---------------- 任务列表 ----------------

    /** 任务列表 + 分页；DONE 且 token 未过期附 downloadUrl，过期则 downloadUrl=null + error */
    public Map<String, Object> listJobs(Integer shopId, int page, int pageSize, String jobType, String status) {
        QueryWrapper<ReportExportJob> q = new QueryWrapper<>();
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        if (jobType != null && !jobType.trim().isEmpty()) {
            q.eq("job_type", jobType.trim());
        }
        if (status != null && !status.trim().isEmpty()) {
            q.eq("status", status.trim());
        }
        q.orderByDesc("id");
        int pn = page > 0 ? page : 1;
        int ps = pageSize > 0 ? Math.min(pageSize, 100) : 20;
        IPage<ReportExportJob> p = reportExportJobMapper.selectPage(new Page<>(pn, ps), q);
        List<Map<String, Object>> items = new ArrayList<>();
        LocalDateTime now = LocalDateTime.now(ZONE);
        for (ReportExportJob job : p.getRecords()) {
            items.add(buildJobItem(job, now));
        }
        PageResult pr = PageResult.of(pn, ps, p.getTotal(), items);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("page", pr.getPage());
        out.put("pageSize", pr.getPageSize());
        out.put("total", pr.getTotal());
        out.put("items", pr.getItems());
        return out;
    }

    /** 单个任务的对外视图（下载链接短期有效判断也在此） */
    public Map<String, Object> buildJobItem(ReportExportJob job, LocalDateTime now) {
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("jobId", job.getId());
        item.put("jobType", job.getJob_type());
        item.put("reportType", job.getReport_type());
        item.put("format", job.getFormat());
        item.put("status", job.getStatus());
        item.put("fileName", job.getFile_name());
        item.put("createdAt", iso(job.getCreated_at()));
        item.put("updatedAt", iso(job.getUpdated_at()));
        if (job.getResult_summary_json() != null) {
            item.put("resultSummary", parseSummary(job.getResult_summary_json()));
        }
        if (ReportExportJob.STATUS_DONE.equals(job.getStatus())) {
            if (isDownloadTokenUsable(job, now)) {
                item.put("downloadUrl", String.format("/admin/reports/exports/%d/download?token=%s",
                        job.getId(), job.getDownload_token()));
                item.put("tokenExpiresAt", iso(job.getToken_expires_at()));
            } else {
                item.put("downloadUrl", null);
                item.put("error", MSG_LINK_EXPIRED);
            }
        } else if (job.getError() != null) {
            item.put("error", job.getError());
        }
        return item;
    }

    /**
     * 下载令牌可用性：DONE + token 非空一致 + 未过期。
     * 公开静态方法便于单测（导出任务 token 过期判断用例）。
     */
    public static boolean isDownloadTokenUsable(ReportExportJob job, LocalDateTime now) {
        if (job == null || !ReportExportJob.STATUS_DONE.equals(job.getStatus())) {
            return false;
        }
        if (job.getDownload_token() == null || job.getDownload_token().trim().isEmpty()) {
            return false;
        }
        return job.getToken_expires_at() != null && now.isBefore(job.getToken_expires_at());
    }

    // ---------------- 下载 ----------------

    /** 校验 token 与有效期，返回可下载文件路径；不通过抛稳定错误码 */
    public Path resolveDownload(Integer shopId, Long jobId, String token) {
        ReportExportJob job = reportExportJobMapper.selectById(jobId);
        if (job == null || (shopId != null && !shopId.equals(job.getShop_id()))) {
            throw new ApiException(404, "REPORT_JOB_NOT_FOUND", "导出任务不存在");
        }
        if (token == null || token.trim().isEmpty() || !token.trim().equals(job.getDownload_token())) {
            throw new ApiException(400, "DOWNLOAD_TOKEN_INVALID", "下载令牌无效");
        }
        if (!isDownloadTokenUsable(job, LocalDateTime.now(ZONE))) {
            throw new ApiException(410, "DOWNLOAD_LINK_EXPIRED", "下载链接已过期，请重新导出");
        }
        Path file = Paths.get(exportDir).resolve(job.getFile_name());
        if (!Files.exists(file)) {
            throw new ApiException(404, "REPORT_FILE_MISSING", "导出文件不存在或已被清理");
        }
        return file;
    }

    // ---------------- 工具 ----------------

    private Map<String, Object> parseFilters(String json) {
        if (json == null || json.trim().isEmpty()) {
            return new LinkedHashMap<>();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<LinkedHashMap<String, Object>>() {
            });
        } catch (Exception e) {
            throw new ApiException(500, "REPORT_FILTER_PARSE_FAILED", "任务筛选条件解析失败");
        }
    }

    public Map<String, Object> parseSummary(String json) {
        if (json == null || json.trim().isEmpty()) {
            return new LinkedHashMap<>();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<LinkedHashMap<String, Object>>() {
            });
        } catch (Exception e) {
            Map<String, Object> raw = new LinkedHashMap<>();
            raw.put("raw", json);
            return raw;
        }
    }

    String json(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            throw new ApiException(500, "REPORT_SERIALIZE_FAILED", "筛选条件序列化失败");
        }
    }

    static String str(Map<String, Object> m, String key) {
        if (m == null) {
            return "";
        }
        Object v = m.get(key);
        return v == null ? "" : String.valueOf(v).trim();
    }

    static String iso(LocalDateTime time) {
        return time == null ? null : time.atZone(ZONE).format(ISO);
    }

    private static String truncate(String s, int limit) {
        return s.length() <= limit ? s : s.substring(0, limit);
    }

    /** 供 AdminLogService 复用的任务持久化入口（同库同表） */
    public void insertJob(ReportExportJob job) {
        if (ReportExportJob.TYPE_ARCHIVE_SEARCH.equals(job.getJob_type()))
            jobCoordinator.admit(job.getShop_id(), () -> reportExportJobMapper.insert(job));
        else reportExportJobMapper.insert(job);
    }

    public ReportExportJob getJob(Integer shopId, Long jobId, String expectedJobType) {
        ReportExportJob job = reportExportJobMapper.selectById(jobId);
        if (job == null || (shopId != null && !shopId.equals(job.getShop_id()))) {
            return null;
        }
        if (expectedJobType != null && !expectedJobType.equals(job.getJob_type())) {
            return null;
        }
        return job;
    }

    public void updateJob(ReportExportJob job) {
        reportExportJobMapper.updateById(job);
    }
}
