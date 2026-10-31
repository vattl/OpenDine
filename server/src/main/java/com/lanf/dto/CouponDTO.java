package com.lanf.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.util.Date;


@Data
public class CouponDTO {
    private Long id;
    private String coupon_name;
    private String coupon_type;
    private BigDecimal discount_value;
    private BigDecimal min_amount;
    private String apply_dining_type;
    private String description;
    private Date start_time;
    private Date end_time;
    private Integer stock;
    private Boolean has_received; // 是否已领取
}