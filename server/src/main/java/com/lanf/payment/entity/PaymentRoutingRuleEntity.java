package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_payment_routing_rule")
public class PaymentRoutingRuleEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private String channel;

    private String rule_name;

    private Integer priority;

    /** 1: 启用, 0: 停用 */
    private Integer enabled;

    private String target_merchant_key;

    /** ALL: 满足所有条件 (AND), ANY: 满足任一条件 (OR) */
    private String match_mode;

    private String conditions_json;

    private String remark;

    private Date created_at;

    private Date updated_at;
}
