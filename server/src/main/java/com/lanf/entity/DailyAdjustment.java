package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Date;

/**
 * 营业日关账后调整台账 (t_daily_adjustment)
 * 记录已关账营业日后续发生的退款、人工补录或调整，不篡改原快照
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_daily_adjustment")
public class DailyAdjustment {

    public static final String TYPE_POST_CLOSE_REFUND = "POST_CLOSE_REFUND";
    public static final String TYPE_POST_CLOSE_CASH = "POST_CLOSE_CASH";
    public static final String TYPE_MANUAL_ADJUSTMENT = "MANUAL_ADJUSTMENT";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 调整单号 (ADJ...) */
    private String adjustment_no;

    /** 关联日结快照ID */
    private Long snapshot_id;

    /** 门店ID */
    private Integer shop_id;

    /** 归属营业日 (YYYY-MM-DD) */
    private String business_day;

    /** 调整类型：POST_CLOSE_REFUND / POST_CLOSE_CASH / MANUAL_ADJUSTMENT */
    private String adjustment_type;

    /** 调整金额(分)，退款为负，补录为正 */
    private Integer amount_fen;

    /** 关联订单ID */
    private Long order_id;

    /** 关联支付流水ID */
    private Long payment_ledger_id;

    /** 调整原因说明 */
    private String reason;

    /** 经办人ID */
    private Integer operator_id;

    /** 审批人ID */
    private Integer approved_by;

    /** 创建时间 */
    private Date created_at;
}
