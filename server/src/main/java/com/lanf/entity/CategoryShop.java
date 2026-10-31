package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/** 当前门店的分类展示顺序覆盖。 */
@Data
@TableName("t_category_shop")
public class CategoryShop {
    private Long id;
    private Integer shop_id;
    private Integer category_id;
    private Integer sorting_override;
    private Date updated_at;
}

