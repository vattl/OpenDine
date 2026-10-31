package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;

@Data
@TableName("t_combo_group_item")
public class ComboGroupItem {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long group_id;

    private Integer component_dish_id;

    private BigDecimal extra_price;

    private Integer sort_order;
}
