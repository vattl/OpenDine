package com.lanf.dto;

import lombok.Data;

/**
 * 历史窗口内按「周一=1…周日=7」与菜品名汇总的销量，供备货预测使用。
 * 与 {@link com.lanf.mapper.OrderMapper#listDishDowDemandStats} 结果映射一致。
 */
@Data
public class DishDowDemandStatDTO {
    /** ISO 星期：周一=1 … 周日=7 */
    private Integer isoDow;
    /** 订单明细菜品名（trim 后） */
    private String dishName;
    /** 该星期几上的销量合计 */
    private Long totalQty;
}
