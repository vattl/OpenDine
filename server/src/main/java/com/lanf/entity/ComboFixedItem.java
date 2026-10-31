package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

@Data
@TableName("t_combo_fixed_item")
public class ComboFixedItem {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long combo_id;

    private Integer component_dish_id;

    private Integer qty_per_combo;

    private Integer sort_order;
}
