package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 备货预测按日按菜，对应 t_stock_prep_forecast_dish
 */
@Data
@TableName("t_stock_prep_forecast_dish")
public class StockPrepForecastDish {
    private Long id;
    private Long run_id;
    private Date stat_date;
    private Integer dish_id;
    private String dish_name;
    private BigDecimal baseline_avg;
    private Integer predicted_servings;
    private Integer actual_quantity;
    private Date validated_at;
}
