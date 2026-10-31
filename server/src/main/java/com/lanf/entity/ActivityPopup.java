package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
import org.springframework.format.annotation.DateTimeFormat;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 活动弹窗实体类
 */
@Data
@TableName("t_activity_popup")
public class ActivityPopup {

    @TableId(type = IdType.AUTO)
    private Long id;


    private String name;


    private String popup_image;

    private String image_url;

    /**
     * 目标用户：new/member/all
     */
    private String target_user;

    /**
     * 开始时间
     */
    @DateTimeFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private Date start_time;

    /**
     * 结束时间
     */
    @DateTimeFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private Date end_time ;

    /**
     * 是否启用：1-启用 0-禁用
     */
    private Integer is_enabled;

    /**
     * 活动投入预算（元），可选；用于数据分析 ROI。
     * 未执行 {@code docs/db_migration_activity_popup_budget.sql} 前库表无此列，须标记 exist=false，避免 MP 生成 SQL 引用该列。
     * 迁移并增加列后，去掉本注解上的 {@code exist = false}，并把 AnalyticsMapper.selectActivityPopupStats 中 budget_amount 改为读表字段。
     */
    @TableField(value = "budget_amount", exist = false)
    private BigDecimal budget_amount;

    /**
     * 单日最大展示次数
     */

    private Integer max_show_count;

    /**
     * 创建时间
     */

    private Date created_at;

    private Integer sorting;

    /**轮播图：home_top/home_bottom/page_banner/page_hor/page_activity*/
    private String type;

    /**
     * 适用门店 ID 列表，JSON 数组字符串，如 {@code [1,5,3]}；
     * NULL / 空 / {@code []} 表示全部门店可见。
     */
    private String apply_shop_ids;

}
