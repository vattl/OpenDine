package com.lanf.ai.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 餐桌成员偏好画像表 (餐桌 DNA)，对应 t_dining_session_member
 */
@Data
@TableName("t_dining_session_member")
public class DiningSessionMember {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String session_id;

    /** 成员代号，如 P1, P2 */
    private String diner_id;

    private String alias;

    /** 是否不吃辣：1 是，0 否 */
    private Integer is_non_spicy;

    /** 忌口食材JSON，如 ["牛肉","葱"] */
    private String disliked_ingredients;

    /** 过敏原JSON，如 ["PEANUT"] */
    private String verified_allergens;

    /** 食量要求：small, normal, large */
    private String portion_target;

    /** 个人健身目标JSON，如 ["high_protein","low_fat"] */
    private String fitness_goals;

    /** 是否参与共享菜：1 是，0 否 */
    private Integer join_shared_dishes;

    private Date created_at;
}
