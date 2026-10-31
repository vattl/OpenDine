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
 * 跨店会员储值消费清算明细
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_member_cross_shop_clearing")
public class MemberCrossShopClearing {

    public static final String STATUS_PENDING = "PENDING";
    public static final String STATUS_SETTLED = "SETTLED";

    @TableId(type = IdType.AUTO)
    private Long id;

    private String order_no;

    private Integer user_id;

    /** 充值来源门店ID（出资方/债务方） */
    private Integer source_shop_id;

    /** 消费发生门店ID（服务提供方/债权方） */
    private Integer consume_shop_id;

    private BigDecimal principal_amount;

    private BigDecimal gift_amount;

    private BigDecimal total_amount;

    private String clearing_status;

    private Date settled_at;

    private Date created_at;
}
