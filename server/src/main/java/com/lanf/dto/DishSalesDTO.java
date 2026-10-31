package com.lanf.dto;

import lombok.Data;

/**
 * 按菜品统计销售额，与 OrderMapper.statisticsDishSales 查询结果一致。
 */
@Data
public class DishSalesDTO {
    /** 菜品名称（来自 t_order_detail.name） */
    private String dish_name;
    /** 该菜品在时间范围内的销售总额（SUM(total_price)） */
    private String total_sales;
    /** 该菜品在时间范围内的销售总数量（SUM(quantity)） */
    private Long total_quantity;
}
