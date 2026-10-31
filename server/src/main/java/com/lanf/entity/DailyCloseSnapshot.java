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
 * 营业日关账不可变快照 (t_daily_close_snapshot)
 * 记录固定营业窗口与账本截止水位后的不可变财务关账数据
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_daily_close_snapshot")
public class DailyCloseSnapshot {

    public static final String STATE_PREVIEW = "PREVIEW";
    public static final String STATE_CLOSING = "CLOSING";
    public static final String STATE_CLOSED = "CLOSED";
    public static final String STATE_REOPENED = "REOPENED";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 日结快照编号 (DSN...) */
    private String snapshot_no;

    /** 门店ID */
    private Integer shop_id;

    /** 归属营业日 (YYYY-MM-DD) */
    private String business_day;

    /** 营业窗口开始时间 */
    private Date window_start;

    /** 营业窗口截止时间 */
    private Date window_end;

    /** 状态：PREVIEW/CLOSING/CLOSED/REOPENED */
    private String state;

    /** 账本截止水位ID (t_payment_ledger) */
    private Long cutoff_ledger_id;

    /** 现金动作截止水位ID (t_cash_movement) */
    private Long cutoff_movement_id;

    /** 订单截止水位ID (t_order) */
    private Long cutoff_order_id;

    /** 会员充值截止水位ID (t_member_recharge) */
    private Long cutoff_recharge_id;

    /** 应收流水截止水位ID */
    private Long cutoff_receivable_ledger_id;

    /** 总营业额(分) */
    private Long total_sales_fen;

    /** 优惠折扣总额(分) */
    private Long discount_amount_fen;

    /** 退款总额(分) */
    private Long refund_amount_fen;

    /** 净销售额(分，包含挂账销售，不等同于实际收款) */
    private Long net_sales_fen;

    /** 成交订单总数 */
    private Integer order_count;

    /** 钱箱班次数量 */
    private Integer drawer_session_count;

    /** 钱箱现金长短款累计(分) */
    private Integer total_cash_variance_fen;

    /** 会员储值本金(分) */
    private Long member_recharge_fen;

    /** 会员储值赠送额(分)，不计实际收款 */
    private Long member_recharge_gift_fen;

    /** 成功会员充值笔数 */
    private Integer member_recharge_count;

    /** 本营业窗口新增应收、实际回款、坏账及关账时未清余额（分） */
    private Long receivable_charged_fen;
    private Long receivable_collected_fen;
    private Long receivable_writeoff_fen;
    private Long receivable_reversed_fen;
    private Long receivable_outstanding_fen;

    /** 真实收款合计：支付台账净额 + 应收回款 + 充值本金 */
    private Long total_collections_fen;

    /** 各支付渠道实收明细JSON */
    private String channel_breakdown_json;

    /** 钱箱流水公式与现金盘点汇总JSON */
    private String drawer_summary_json;

    /** 不可变数据SHA-256摘要哈希 */
    private String snapshot_hash;

    /** 日结写入幂等键 */
    private String settle_idempotency_key;

    /** 日结经办人管理员ID */
    private Integer operator_id;

    /** 日结经办人姓名 */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String operator_name;

    /** 日结复核/审批人ID */
    private Integer reviewer_id;

    /** 日结复核/审批人姓名 */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String reviewer_name;

    /** 重开时间 */
    private Date reopened_at;

    /** 重开操作人ID */
    private Integer reopened_by;

    /** 重开操作人姓名 */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String reopened_by_name;

    /** 重开原因 */
    private String reopen_reason;

    /** 关账完成时间 */
    private Date closed_at;

    /** 创建时间 */
    private Date created_at;

    /** 更新时间 */
    private Date updated_at;
}
