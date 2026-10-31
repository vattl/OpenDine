package com.lanf.dto;

import lombok.Data;

/**
 * 分类销售额统计项，与 OrderMapper.statisticsCategorySales 查询结果一致。
 * 注意：库表 t_order_detail.cid、t_category.cid 为 varchar，故 cid 使用 String。
 */
@Data
public class CategorySalesDTO {
    /** 分类 id（来自 t_order_detail.cid，实际为字符串如 a20250523022119000000933） */
    private String cid;
    private String category_name;
    private String total_sales;

}