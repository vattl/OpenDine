package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 备货预测按日汇总，对应 t_stock_prep_forecast_day
 */
@Data
@TableName("t_stock_prep_forecast_day")
public class StockPrepForecastDay {
    private Long id;
    private Long run_id;
    private Date stat_date;
    private Integer iso_day_of_week;
    private String day_kind;
    private Integer is_holiday;
    private String holiday_name;
    private BigDecimal factor_holiday;
    private BigDecimal factor_weather;
    private BigDecimal factor_composite;
    private Integer weather_available;
    private String weather_summary;
    private Integer weather_code;
    private Integer weather_precip_prob;
    private BigDecimal weather_temp_max;
    private Integer predicted_servings_sum;
    private Integer actual_servings_forecast_dishes;
    private Integer actual_servings_all_dishes;
    private Integer actual_order_count;
    private BigDecimal daily_stat_total_amount;
    private BigDecimal daily_stat_discount_amount;
    private BigDecimal daily_stat_refund_amount;
    private BigDecimal daily_stat_material_cost;
    private Integer daily_stat_settled;
    private Date day_validated_at;
}
