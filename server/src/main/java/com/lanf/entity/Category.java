package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.List;

/**
 * 菜单类别
 */
@TableName("t_category")
@Data
public class Category {

    private Integer id; // 编号

    private String label; // 名称

    private String value; // 值

    private Integer count; // 数量

    private Integer sele_quantity; // 选择数量

    private String cid; //  id标识

    @TableField(select = false)
    private List<Dish> dishList; // 拥有的菜品

    private Integer sorting;  // 商品排序
}
