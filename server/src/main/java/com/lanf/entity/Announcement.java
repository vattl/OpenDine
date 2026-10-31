package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 门店公告（连锁），对应 t_announcement。
 */
@Data
@TableName("t_announcement")
public class Announcement {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** NULL=全部门店可见 */
    private Integer shop_id;

    private String title;

    private String content;

    /** 1=启用 0=停用 */
    private Integer status;

    private Integer sort_order;

    private Date start_time;

    private Date end_time;

    private Date created_at;

    private Date updated_at;
}
