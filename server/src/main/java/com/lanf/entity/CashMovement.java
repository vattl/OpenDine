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
 * 不可表现金动作账本 (t_cash_movement)
 * 记录收银钱箱的全部现金流入、流出、清点与调整
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_cash_movement")
public class CashMovement {

    /** 备用金录入 */
    public static final String TYPE_OPENING_FLOAT = "OPENING_FLOAT";
    /** 现金销售结账（正数） */
    public static final String TYPE_CASH_SALE = "CASH_SALE";
    /** 现金退款/反结账现金冲正（负数） */
    public static final String TYPE_CASH_REFUND = "CASH_REFUND";
    /** 现金存入/临时加钞（正数） */
    public static final String TYPE_CASH_IN = "CASH_IN";
    /** 现金取出/临时支取（负数） */
    public static final String TYPE_CASH_OUT = "CASH_OUT";
    /** 投库/大钞上缴保险柜（负数） */
    public static final String TYPE_CASH_DROP = "CASH_DROP";
    /** 关班盘点记录 */
    public static final String TYPE_COUNT = "COUNT";
    /** 盘点差额平账调整（正/负） */
    public static final String TYPE_ADJUSTMENT = "ADJUSTMENT";
    /** 开箱不交易/清点弹箱（0金额） */
    public static final String TYPE_NO_SALE = "NO_SALE";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 动作流水号 */
    private String movement_no;

    /** 关联钱箱会话ID */
    private Long drawer_session_id;

    /** 门店ID */
    private Integer shop_id;

    /** 动作类型 */
    private String movement_type;

    /** 变动金额(分)，流入为正，流出为负 */
    private Integer amount_fen;

    /** 动作发生后推导钱箱当前现金余额(分) */
    private Integer current_balance_fen;

    /** 原因代码 */
    private String reason_code;

    /** 备注说明 */
    private String remark;

    /** 经办操作人管理员ID */
    private Integer operator_id;

    /** 审批人管理员ID */
    private Integer approver_id;

    /** 关联订单ID */
    private Long order_id;

    /** 关联订单号 */
    private String order_no;

    /** 关联不可变支付台账ID */
    private Long payment_ledger_id;

    /** 幂等请求键 */
    private String request_id;

    /** 动作发生时间 */
    private Date occurred_at;

    /** 落账创建时间 */
    private Date created_at;
}
