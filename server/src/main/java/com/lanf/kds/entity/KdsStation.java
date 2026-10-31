package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_station")
public class KdsStation {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private String name;

    private String code;

    private String screen_tag;

    private Integer sort;

    private Integer enabled;

    /** 1=启用待配菜环节；0=关闭待配菜；null=继承门店配置 */
    private Integer enable_prep_workflow;

    private Date created_at;

    private Date updated_at;
}
