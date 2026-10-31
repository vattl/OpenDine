package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

@Data
@TableName("t_combo_group")
public class ComboGroup {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long combo_id;

    private String group_key;

    private String title;

    private Integer min_pick;

    private Integer max_pick;

    private Integer sort_order;
}
