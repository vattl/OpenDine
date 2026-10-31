package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 订单电子发票开具申请实体，对应表 t_order_invoice
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_order_invoice")
public class OrderInvoice {

    /** 待扫码填写发票抬头 */
    public static final String STATUS_PENDING_SCAN = "PENDING_SCAN";
    /** 用户已提交发票抬头 */
    public static final String STATUS_TITLE_SUBMITTED = "TITLE_SUBMITTED";
    /** 发票开具中 */
    public static final String STATUS_ISSUING = "ISSUING";
    /** 开票成功并交付卡包 */
    public static final String STATUS_SUCCESS = "SUCCESS";
    /** 开票失败 */
    public static final String STATUS_FAILED = "FAILED";
    /** 申请被财务驳回 */
    public static final String STATUS_REJECTED = "REJECTED";
    /** 发票已冲红 */
    public static final String STATUS_REVERSED = "REVERSED";

    /** 卡包插卡状态常量 */
    public static final String CARD_STATUS_NOT_ATTEMPTED = "NOT_ATTEMPTED";
    public static final String CARD_STATUS_PENDING = "PENDING";
    public static final String CARD_STATUS_SUCCESS = "SUCCESS";
    public static final String CARD_STATUS_FAILED = "FAILED";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 关联订单号 */
    private String order_no;

    /** 所属门店ID */
    private Integer shop_id;

    /** 所属门店名称（独立纳税主体） */
    @TableField(exist = false)
    private String shop_name;

    /** 所属门店编码 */
    @TableField(exist = false)
    private String shop_code;

    /** 所属门店地址（用于定位所属税务机关与电子税局） */
    @TableField(exist = false)
    private String shop_address;

    /** 所属电子税务局开票门户全称 */
    @TableField(exist = false)
    private String tax_bureau_name;

    /** 所属电子税务局开票门户入口URL */
    @TableField(exist = false)
    private String tax_bureau_url;

    /** 微信发票申请单号（唯一标识一次开票请求） */
    private String fapiao_apply_id;

    /** 开票状态 */
    private String invoice_status;

    /** 申请开票金额(元) */
    private BigDecimal invoice_amount;

    /** 税率，默认 0.06 */
    private BigDecimal tax_rate;

    /** 顾客扫码开票二维码链接/小程序路径 */
    private String invoice_qr_url;

    /** 访问token SHA-256哈希 */
    private String token_hash;

    /** token有效期截止时间 */
    private Date token_expire_at;

    /** token首次使用/提交时间 */
    private Date token_used_at;

    /** 购方发票抬头名称（企业或个人） */
    private String buyer_title;

    /** 购方纳税人识别号 */
    private String buyer_tax_no;

    /** 购方手机号 */
    private String buyer_phone;

    /** 购方接收电子发票邮箱 */
    private String buyer_email;

    /** 发票号码 */
    private String fapiao_number;

    /** 发票代码 */
    private String fapiao_code;

    /** 电子发票PDF/OFD文件下载链接 */
    private String fapiao_file_url;

    /** 微信发票卡券模板ID */
    private String card_id;

    /** 微信卡包卡券Code */
    private String card_code;

    /** 微信发票文件媒体ID (fapiao_media_id) */
    private String fapiao_media_id;

    /** 卡包插卡状态: NOT_ATTEMPTED, PENDING, SUCCESS, FAILED */
    private String card_insert_status;

    /** 卡包插卡结果说明/错误原因 */
    private String card_insert_msg;

    /** 卡包插入完成时间 */
    private Date card_inserted_at;

    /** 发起开票的操作人员工ID */
    private Integer operator_id;

    /** 失败原因或备注信息 */
    private String error_msg;

    /** 创建时间 */
    private Date created_at;

    /** 更新时间 */
    private Date updated_at;
}
