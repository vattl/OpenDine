package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 菜品单位实体
 */
@TableName("t_unit")
@Data
public class Unit {

    private Integer id; // 编号

    private String label; // 标签

    private String value; // 值

}
