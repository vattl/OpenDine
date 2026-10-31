package com.lanf.entity;


import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.List;

/**
 * 菜单类别
 */
@TableName("t_banner")
@Data
public class Banner {

    private Integer id; // 编号

    private String image; // 名称

    private String url; // 值

    private Integer status; // 数量

    private String type; // 展示位置：首页 home，底部 bottom（t_banner.type NOT NULL）


}
