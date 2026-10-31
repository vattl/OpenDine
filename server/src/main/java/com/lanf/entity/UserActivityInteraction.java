package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDate;
import java.util.Date;

/**
 * 用户活动交互记录实体类
 */
@Data
@TableName("t_user_activity_interaction")
public class UserActivityInteraction {

    @TableId(type = IdType.AUTO)
    private Long id;

    /**
     * 用户ID
     */

    private Long userId;

    /**
     * 活动ID
     */

    private Long activityId;

    /**
     * 交互类型：show(展示)/click(点击)/close(关闭)
     */

    private String interactionType;

    /**
     * 交互时间
     */

    private Date interactionTime;

    /**
     * 交互日期（用于按日统计）
     */

    private LocalDate date;
}
    