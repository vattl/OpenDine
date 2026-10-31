package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 权限审批流水与令牌实体，对应 t_access_approval
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_access_approval")
public class AccessApproval {

    public static final String STATUS_PENDING = "PENDING";
    public static final String STATUS_APPROVED = "APPROVED";
    public static final String STATUS_CONSUMED = "CONSUMED";
    public static final String STATUS_EXPIRED = "EXPIRED";
    public static final String STATUS_REVOKED = "REVOKED";
    public static final String STATUS_REJECTED = "REJECTED";

    public static final String AUTH_METHOD_PASSWORD = "PASSWORD";
    public static final String AUTH_METHOD_PIN = "PIN";
    public static final String AUTH_METHOD_SESSION = "SESSION";
    public static final String AUTH_METHOD_QR = "QR";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 审批唯一流水号 */
    private String approval_no;

    /** 需要授权的目标权限码 */
    private String permission_code;

    /** 操作人管理员ID */
    private Integer operator_id;

    /** 授权人(店长)管理员ID */
    private Integer authorizer_id;

    /** 门店ID */
    private Integer shop_id;

    /** 业务类型: ORDER, REFUND, CASH_DRAWER, DISCOUNT 等 */
    private String biz_type;

    /** 业务对象唯一标识 (如订单号) */
    private String biz_id;

    /** 申请涉及的业务金额 */
    private BigDecimal amount;

    /** 授权原因 */
    private String reason;

    /** 授权认证方式: PASSWORD, PIN, SESSION */
    private String auth_method;

    /** 状态: PENDING, APPROVED, CONSUMED, EXPIRED, REVOKED, REJECTED */
    private String status;

    /** 短期授权Token的SHA-256哈希值 */
    private String token_hash;

    /** 二维码审批令牌 AES-GCM 短期加密信封（绝不保存原始令牌；核销后置空） */
    private String token_value;

    /** 上下文绑定策略版本：1=兼容模式，2=动作/资源/金额/操作者/门店/终端严格绑定 */
    private Integer binding_version;

    /** 授权允许的最大金额上限 */
    private BigDecimal max_amount;

    /** Token有效截止时间 */
    private Date expires_at;

    /** Token核销消费时间 */
    private Date consumed_at;

    /** 客户端幂等请求标识 */
    private String request_id;

    /** 终端编号 */
    private String terminal_id;

    private Date created_at;
}
