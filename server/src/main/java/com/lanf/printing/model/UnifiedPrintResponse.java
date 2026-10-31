package com.lanf.printing.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;

/**
 * 统一出票调度响应 DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UnifiedPrintResponse implements Serializable {

    private static final long serialVersionUID = 1L;

    /** 关联订单号 */
    @JsonProperty("order_no")
    private String orderNo;

    /** 最终执行的场景小写机器码 */
    private String scenario;

    /** 场景中文名称 */
    @JsonProperty("scenario_name")
    private String scenarioName;

    /** 是否为补打单 */
    @JsonProperty("is_reprint")
    private boolean isReprint;

    /** 调度生成的打印任务总数 */
    @JsonProperty("job_count")
    private int jobCount;

    /** 成功下发数 */
    @JsonProperty("success_count")
    private int successCount;

    /** 失败数 */
    @JsonProperty("failed_count")
    private int failedCount;

    /** 汇总消息提示 */
    private String summary;

    /** 下发任务明细列表 */
    @Builder.Default
    private List<JobItem> jobs = new ArrayList<>();

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class JobItem implements Serializable {
        private static final long serialVersionUID = 1L;

        @JsonProperty("job_id")
        private Long jobId;

        @JsonProperty("device_id")
        private Long deviceId;

        @JsonProperty("device_name")
        private String deviceName;

        private String transport;

        private String status;

        private boolean success;

        private String error;
    }
}
