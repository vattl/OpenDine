package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_dish_screen")
public class KdsDishScreen {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private Integer dish_id;

    private String screen_tag;

    private Date created_at;

    private Date updated_at;
}
