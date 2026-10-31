package com.lanf.dto;

import lombok.Data;
import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

/**
 * 领取优惠请求DTO
 */
@Data
public class CouponReceiveDTO {
    /**
     * 用户ID
     */
    @NotNull(message = "用户ID不能为空")
    private Long user_id;

    /**
     * 省份简称
     */
    @NotBlank(message = "省份不能为空")
    private String province;

    /**
     * 车牌号（不含省份）
     */
    @NotBlank(message = "车牌号不能为空")
    private String plate_number;

    /**
     * 车牌类型 1-燃油车 2-新能源车
     */
    @NotNull(message = "车牌类型不能为空")
    private Integer plate_type;


}