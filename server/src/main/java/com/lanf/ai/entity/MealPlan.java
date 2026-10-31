package com.lanf.ai.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * AI智能配餐候选方案实体，对应 t_meal_plan
 */
@Data
@TableName("t_meal_plan")
public class MealPlan {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String plan_id;

    private String session_id;

    private Integer revision;

    private String menu_version;

    private String strategy;

    /** 方案核算总价(分) */
    private Integer price_total_fen;

    /** 剩余预算(分) */
    private Integer remaining_budget_fen;

    /** 是否完全可行：1 是，0 否 */
    private Integer feasible;

    /** 推荐商品列表JSON */
    private String line_items_json;

    /** 成员分配矩阵JSON */
    private String allocation_matrix_json;

    /** 解释卡文案JSON */
    private String explanation_cards_json;

    /** 各项打分明细JSON */
    private String score_details_json;

    /** 不可行时的冲突诊断与最小可行预算JSON */
    private String conflict_details_json;

    private Date created_at;
}
