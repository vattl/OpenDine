package com.lanf.report.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 报表/日志导出与归档检索任务，对应 t_report_export_job。
 * job_type 区分三类任务：REPORT_EXPORT（报表导出）、LOG_EXPORT（日志导出，同步生成）、
 * ARCHIVE_SEARCH（归档日志异步检索）。字段命名沿用本项目 snake_case 惯例。
 */
@Data
@TableName("t_report_export_job")
public class ReportExportJob {

    public static final String TYPE_REPORT_EXPORT = "REPORT_EXPORT";
    public static final String TYPE_LOG_EXPORT = "LOG_EXPORT";
    public static final String TYPE_ARCHIVE_SEARCH = "ARCHIVE_SEARCH";

    public static final String STATUS_PENDING = "PENDING";
    public static final String STATUS_RUNNING = "RUNNING";
    public static final String STATUS_DONE = "DONE";
    public static final String STATUS_FAILED = "FAILED";

    public static final String FORMAT_CSV = "csv";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 门店隔离维度 t_shop.id */
    private Integer shop_id;

    /** 任务类型：REPORT_EXPORT/LOG_EXPORT/ARCHIVE_SEARCH */
    private String job_type;

    /** 报表类型：daily/weekly/monthly；日志类任务为 log */
    private String report_type;

    /** 筛选条件 JSON */
    private String filters_json;

    /** 导出格式：csv/xlsx（当前实现仅 csv） */
    private String format;

    /** 状态：PENDING/RUNNING/DONE/FAILED */
    private String status;

    /** 生成文件名（服务端 ./data/exports 目录下） */
    private String file_name;

    /** 32 位随机下载令牌 */
    private String download_token;

    /** 下载令牌过期时间（生成后 15 分钟） */
    private LocalDateTime token_expires_at;

    /** 结果摘要 JSON（归档查询存命中数/窗口/提示） */
    private String result_summary_json;

    /** 失败原因或过期提示 */
    private String error;

    /** 创建管理员 t_admin.id */
    private Integer created_by;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;

    @com.fasterxml.jackson.annotation.JsonIgnore
    private String run_token;
    @com.fasterxml.jackson.annotation.JsonIgnore
    private LocalDateTime lease_until;
}
