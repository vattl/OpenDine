package com.lanf.ai.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 餐桌协同点餐会话表，对应 t_dining_session
 */
@Data
@TableName("t_dining_session")
public class DiningSession {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String session_id;

    private Integer shop_id;

    private String table_number;

    private Integer party_size;

    /** 总预算 (整型分，如15000代表150元) */
    private Integer budget_fen;

    private String currency;

    /** dine_in / take_out */
    private String dining_mode;

    /** 预算是否包含酒水饮料：0 否，1 是 */
    private Integer include_drinks;

    /** balanced, budget_first, satiety_first, high_protein */
    private String strategy;

    /** 全桌共享目标JSON，如 ["fitness","weightloss"] */
    private String table_goals;

    /** 乐观锁版本号，每次修改递增 */
    private Integer revision;

    /** COLLECTING, PROPOSED, INFEASIBLE, CONFIRMED, EXPIRED */
    private String status;

    private String active_plan_id;

    private Date expires_at;

    private Date created_at;

    private Date updated_at;
}
