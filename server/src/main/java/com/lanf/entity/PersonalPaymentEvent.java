package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.io.Serializable;
import java.math.BigDecimal;
import java.util.Date;

/**
 * 个人收款通知事件日志记录（用于幂等去重与财务对账）
 */
@Data
@TableName("t_personal_payment_event")
public class PersonalPaymentEvent implements Serializable {
    private static final long serialVersionUID = 1L;

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 客户端/App 唯一事件 ID */
    private String event_id;

    /** 收款渠道（alipay / wechat） */
    private String channel;

    /** 到账金额（分） */
    private Long amount_fen;

    /** 到账金额（元） */
    private BigDecimal amount_yuan;

    /** 原始时间戳 */
    private String timestamp_raw;

    /** 原始到账通知文本 */
    private String raw_text;

    /** 匹配到的门店 ID */
    private Integer matched_shop_id;

    /** 匹配到的订单号 */
    private String matched_order_no;

    /** 状态：PROCESSED, MATCHED, UNMATCHED */
    private String status;

    /** 备注说明 */
    private String remark;

    /** 创建时间 */
    private Date created_at;
}
