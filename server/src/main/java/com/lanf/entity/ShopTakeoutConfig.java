package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 门店外卖开关与费用，对应 t_shop_takeout_config（主键 shop_id）。
 */
@Data
@TableName("t_shop_takeout_config")
public class ShopTakeoutConfig {

    @TableId(type = IdType.INPUT)
    private Integer shop_id;

    /** 1=开启外卖 */
    private Integer enabled;

    private BigDecimal delivery_fee;

    private BigDecimal min_order_amount;

    private BigDecimal free_delivery_threshold;

    /** 最远配送距离（公里），超出不可下单 */
    private BigDecimal max_delivery_distance_km;

    /** 满额免配送费适用的最远距离（公里） */
    private BigDecimal free_delivery_max_distance_km;

    /**
     * 距离阶梯运费 JSON，升序 toKm，如
     * [{"toKm":3,"fee":5},{"toKm":4,"fee":8},{"toKm":5,"fee":10}]
     */
    private String delivery_fee_tiers_json;

    private Integer lead_time_minutes;

    private String remark;

    /** 1=启用真省钱聚合配送 */
    private Integer zsq_enabled;

    /** 1=商家接单后自动发真省钱配送 */
    private Integer zsq_auto_dispatch;

    /** 真省钱发单店铺 id */
    private Long zsq_from_address_id;

    /** 地址解析城市 */
    private String zsq_city_name;

    private Date updated_at;
}
