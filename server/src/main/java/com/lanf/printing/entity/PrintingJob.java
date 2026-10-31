package com.lanf.printing.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 打印任务记录（含打印测试单），对应 t_printing_job。
 * 执行方 executor=CLOUD 时由服务端调用既有飞鹅打印服务（IFeieyunService）；
 * executor=DEVICE（LAN/USB/BLUETOOTH）时任务停留在 PENDING_DEVICE，由端侧领取执行。
 * 本模块不提供任何「远程重启打印服务」能力。
 */
@TableName("t_printing_job")
@Data
public class PrintingJob {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** t_shop.id，门店隔离维度 */
    private Integer shop_id;

    /** t_printing_device.id */
    private Long device_id;

    /**
     * 标准场景码：十一类内置场景或合法自定义码。
     * 历史数据可能仍为 order/serve 等别名，读取时由 PrintScenario 归一化。
     */
    private String job_type;

    /** 状态：PENDING_DEVICE/SENT/PRINTED/FAILED/CANCELED */
    private String status;

    /** 打印内容文本 */
    private String payload_text;

    /** 失败原因 */
    private String error;

    /** 已重试次数（仅记录） */
    private Integer retry_count;

    /** 执行方：CLOUD/DEVICE */
    private String executor;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;

    /** 业务类型：kds_serve（KDS 划菜）等；用于按业务键反查打印记录 */
    private String biz_type;

    /** 业务主键：如 t_order_detail.id */
    private Long biz_id;
}
