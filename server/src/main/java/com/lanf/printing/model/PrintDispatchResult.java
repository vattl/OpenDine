package com.lanf.printing.model;

import lombok.Data;

/**
 * 打印派发执行结果
 */
@Data
public class PrintDispatchResult {

    /** 数据库生成的任务 ID */
    private Long jobId;

    /** 格式化业务任务编号，如 JOB-PRINT-20260830-101 */
    private String jobCode;

    /** 派发的设备 ID */
    private Long deviceId;

    /** 派发的设备名称 */
    private String deviceName;

    /** 设备连接类型：CLOUD / LAN / USB / BLUETOOTH */
    private String transport;

    /** 打印场景 */
    private String scenario;

    /** 打印份数 */
    private int copies;

    /** 任务状态：SENT / PENDING_DEVICE / PRINTED / FAILED */
    private String status;

    /** 执行方：CLOUD / DEVICE */
    private String executor;

    /** 成功与否 */
    private boolean success;

    /** 提示或响应消息 */
    private String message;

    /** 错误信息（若有） */
    private String error;

    /** 渲染后的文本内容（用于调试或预览） */
    private String payloadText;

    public static PrintDispatchResult sent(long deviceId, long jobId) {
        PrintDispatchResult r = new PrintDispatchResult();
        r.setDeviceId(deviceId);
        r.setJobId(jobId);
        r.setSuccess(true);
        r.setStatus("SENT");
        r.setExecutor("CLOUD");
        return r;
    }

    public static PrintDispatchResult failed(long deviceId, String error) {
        PrintDispatchResult r = new PrintDispatchResult();
        r.setDeviceId(deviceId);
        r.setSuccess(false);
        r.setStatus("FAILED");
        r.setError(error);
        return r;
    }
}
