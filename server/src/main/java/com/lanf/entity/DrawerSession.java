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
 * 终端钱箱会话实体 (t_drawer_session)
 * 同一 (shop_id, terminal_id, drawer_code) 仅允许一个活动会话 (OPEN/CLOSING)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_drawer_session")
public class DrawerSession {

    public static final String STATE_OPEN = "OPEN";
    public static final String STATE_CLOSING = "CLOSING";
    public static final String STATE_CLOSED = "CLOSED";
    public static final String STATE_REOPENED = "REOPENED";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 会话业务流水号 */
    private String session_no;

    /** 门店ID */
    private Integer shop_id;

    /** 收银机终端编号 (如 POS-01) */
    private String terminal_id;

    /** 钱箱代码 (默认 DEFAULT) */
    private String drawer_code;

    /** 状态：OPEN/CLOSING/CLOSED/REOPENED */
    private String state;

    /** 开班操作人管理员ID */
    private Integer opened_by;

    /** 开班操作人姓名 */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String opened_by_name;

    /** 开班时间 */
    private Date opened_at;

    /** 备用金初始金额(分) */
    private Integer opening_float_fen;

    /** 系统计算应有现金(分) */
    private Integer expected_cash_fen;

    /** 实盘现金(分) */
    private Integer counted_cash_fen;

    /** 差额(分) = counted - expected */
    private Integer variance_fen;

    /** 关班人管理员ID */
    private Integer closed_by;

    /** 关班人姓名 */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String closed_by_name;

    /** 关班时间 */
    private Date closed_at;

    /** 长短款差额原因代码 */
    private String variance_reason_code;

    /** 差额详细说明 */
    private String variance_note;

    /** 审批主管管理员ID */
    private Integer approved_by;

    /** 审批主管姓名 */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String approved_by_name;

    /** 审批时间 */
    private Date approved_at;

    /** 归属营业日(YYYY-MM-DD) */
    private String business_day;

    /** 开班幂等请求键 */
    private String request_id;

    /** 关箱交班幂等请求键 */
    private String close_request_id;

    /** 乐观锁版本 */
    private Integer version;

    /** 创建时间 */
    private Date created_at;

    /** 更新时间 */
    private Date updated_at;
}
