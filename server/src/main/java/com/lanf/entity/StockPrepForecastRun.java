package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 备货预测运行批次，对应 t_stock_prep_forecast_run
 */
@Data
@TableName("t_stock_prep_forecast_run")
public class StockPrepForecastRun {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private Date created_at;
    private Integer history_days;
    private Integer forecast_days;
    private Date history_start_date;
    private Date history_end_at;
    private String model_notes;
    private Date last_validated_at;
}
