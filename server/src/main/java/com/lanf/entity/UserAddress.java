package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 小程序用户收货地址，对应 t_user_address。
 */
@Data
@TableName("t_user_address")
public class UserAddress {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String openid;

    private String contact_name;

    private String contact_phone;

    private String tag;

    private String province;

    private String city;

    private String district;

    private String detail_address;

    private BigDecimal lng;

    private BigDecimal lat;

    /** API input/output metadata only; persisted coordinates are always GCJ-02. */
    @TableField(exist = false)
    private String coordinate_type = "gcj02";

    /** 1 默认地址 */
    private Integer is_default;

    private Date created_at;

    private Date updated_at;
}
