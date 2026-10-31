package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 门店备货规则，对应 t_stock_prep_config
 */
@Data
@TableName("t_stock_prep_config")
public class StockPrepConfig {
    private Long id;
    private Integer shop_id;
    private BigDecimal safe_stock_rate;
    private BigDecimal default_loss_rate;
    private Integer forecast_days;
    private Integer history_days;
    private BigDecimal weather_factor;
    private BigDecimal holiday_factor;
    private BigDecimal member_factor;
    private Integer is_enabled;
    private Date updated_at;
}
