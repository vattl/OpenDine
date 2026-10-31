package com.lanf.dto;

import lombok.Data;

/**
 * 单店、单日、单菜品实际销量，与 OrderMapper.listDishActualQtyForShopDay 映射一致。
 */
@Data
public class DishDayActualDTO {
    private String dish_name;
    private Long total_qty;
}
